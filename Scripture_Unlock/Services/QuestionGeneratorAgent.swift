import Foundation

// MARK: - QuestionGeneratorAgent
//
// Orchestrates dynamic trivia-question generation using Gemini.
//
// Flow
// ────
//  1. TriviaService asks for questions for a given pack + difficulty.
//  2. Agent checks its disk cache first.
//  3. If the cache is low (< minCacheThreshold), it triggers an async
//     background generation without blocking the caller.
//  4. Generated questions are validated against the Ethiopian Bible API
//     (verse ref + text sanity check) before being added to the cache.
//  5. On the NEXT alarm the validated questions are available immediately.
//
// The current alarm session ALWAYS gets questions from the cache or the
// static fallback — Gemini latency never blocks alarm dismissal.

@Observable
final class QuestionGeneratorAgent {

    static let shared = QuestionGeneratorAgent()
    private init() {
        loadAllCaches()
    }

    // MARK: - Config

    /// Start background generation when fewer than this many questions remain.
    private let minCacheThreshold = 20
    /// How many questions to request per Gemini call.
    private let batchSize = 15
    /// Maximum cached questions per (packId, difficulty) slot.
    private let maxCacheSize = 60

    // MARK: - State

    /// In-memory cache: ["\(packId)-\(difficulty)": [TriviaQuestion]]
    private var cache: [String: [TriviaQuestion]] = [:]
    /// Tracks which slots are currently being generated (prevent duplicate calls).
    private var generating: Set<String> = []

    // MARK: - Public API

    /// Returns cached generated questions for a slot (synchronous, never nil).
    /// Call `prefetchIfNeeded` separately to keep the cache warm.
    func questions(forPack packId: String, difficulty: Difficulty) -> [TriviaQuestion] {
        cache[cacheKey(packId, difficulty)] ?? []
    }

    /// Checks cache level and triggers background generation if needed.
    /// Safe to call on every alarm fire — deduplicated internally.
    func prefetchIfNeeded(forPack packId: String, difficulty: Difficulty) {
        let key = cacheKey(packId, difficulty)
        let count = cache[key]?.count ?? 0
        guard count < minCacheThreshold, !generating.contains(key) else { return }

        generating.insert(key)
        Task {
            await generateAndCache(packId: packId, difficulty: difficulty)
            _ = await MainActor.run { generating.remove(key) }
        }
    }

    /// Removes a question from the cache once it has been used (called by TriviaService).
    func consume(_ question: TriviaQuestion) {
        let key = cacheKey(question.packId, question.difficulty)
        cache[key]?.removeAll { $0.id == question.id }
        saveCacheToDisk(key: key)
    }

    // MARK: - Generation pipeline

    private func generateAndCache(packId: String, difficulty: Difficulty) async {
        let key         = cacheKey(packId, difficulty)
        let existing    = cache[key] ?? []
        let usedRefs    = Set(existing.map(\.verseRef))
        let targetCount = min(batchSize, maxCacheSize - existing.count)
        guard targetCount > 0 else { return }

        print("[QuestionGeneratorAgent] Generating \(targetCount) questions for \(packId)/\(difficulty.rawValue)")

        do {
            let prompt     = buildPrompt(packId: packId, difficulty: difficulty,
                                         exclude: usedRefs, count: targetCount)
            let jsonString = try await GeminiService.shared.generate(prompt: prompt)
            let raw        = try parseQuestions(from: jsonString, packId: packId, difficulty: difficulty)
            let validated  = await validate(raw)

            await MainActor.run {
                var slot = self.cache[key] ?? []
                for q in validated {
                    if !slot.contains(where: { $0.id == q.id || $0.verseRef == q.verseRef }) {
                        slot.append(q)
                    }
                }
                self.cache[key] = Array(slot.prefix(self.maxCacheSize))
                self.saveCacheToDisk(key: key)
            }

            print("[QuestionGeneratorAgent] Cached \(validated.count) valid questions for \(packId)/\(difficulty.rawValue)")
        } catch {
            print("[QuestionGeneratorAgent] Generation failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Prompt builder

    private func buildPrompt(packId: String, difficulty: Difficulty,
                              exclude usedRefs: Set<String>, count: Int) -> String {
        let pack     = VersePack.find(packId)
        let books    = Self.packBooks[packId] ?? ["Psalms"]
        let bookList = books.joined(separator: ", ")

        let difficultyGuide: String
        switch difficulty {
        case .gentle:
            difficultyGuide = """
            DIFFICULTY — Gentle:
            • Use only very well-known, beloved verses (e.g., Psalm 23:1, John 3:16, Philippians 4:13).
            • For fill questions: blank the single most iconic word — the word a casual Christian would most recognise.
            • For MCQ: ask simple, direct questions. Wrong options should be clearly wrong.
            • Verse text should be from a commonly memorised translation (ESV or KJV-adjacent).
            """
        case .regular:
            difficultyGuide = """
            DIFFICULTY — Regular:
            • Use familiar but not hyper-famous verses. Require genuine verse knowledge.
            • For fill questions: blank a doctrinally important word — not the most obvious one.
            • For MCQ: ask about specific verse details or context. Wrong options should be plausible.
            """
        case .scholar:
            difficultyGuide = """
            DIFFICULTY — Scholar:
            • Use less-quoted but significant verses. Require deep Bible familiarity.
            • For fill questions: blank a key theological term or a specific numerical/proper-noun detail.
            • For MCQ: ask nuanced questions about theological meaning or narrative detail. All wrong options should be plausible enough to require genuine knowledge.
            """
        }

        let excludeClause = usedRefs.isEmpty
            ? "• No exclusions — use your best judgment for variety."
            : "• Do NOT use any of these already-seen references:\n" +
              usedRefs.map { "  – \($0)" }.joined(separator: "\n")

        return """
        You are a precise Bible trivia question generator for "Scripture Unlock" — a Christian morning alarm app where users must answer questions correctly to dismiss their alarm.

        TASK
        Generate exactly \(count) trivia questions from the "\(pack.name)" pack.
        Books in scope: \(bookList)

        \(difficultyGuide)

        VARIETY
        • Mix question types: aim for 60% fill-in-the-blank, 40% multiple choice.
        • Spread across different books and chapters within scope.
        \(excludeClause)

        QUALITY RULES
        1. Every verse reference MUST be real and accurate (book, chapter, verse number must exist).
        2. verseText MUST be the exact ESV verse text — do not paraphrase or combine verses.
        3. Fill questions: blank exactly ONE word. fillPre + " ___ " + fillPost must equal the verseText almost exactly (minor punctuation flexibility is fine).
        4. Fill options: 4 options total — the correct word + 3 plausible distractors from the same verse or thematically related words. All options must be single words or short phrases (≤3 words).
        5. MCQ options: 4 options — 1 correct, 3 plausible-but-wrong. Answers should be names, places, numbers, or short phrases (≤4 words).
        6. answerIndex: 0-based index of the correct answer in the options array. Vary the position — don't always put the right answer at index 0 or 1.
        7. id format: Use uppercase book abbreviation + chapter + verse + kind, e.g. "PSA.23.1-fill" or "JHN.3.16-mcq". For multi-verse refs use the starting verse.

        OUTPUT FORMAT
        Return ONLY a valid JSON array. No markdown, no explanations, no comments.

        Each item in the array must match this exact schema:
        {
          "id": "BOOK.CH.VS-kind",
          "kind": "fill" or "mcq",
          "book": "Full book name (e.g. Psalms, John)",
          "packId": "\(packId)",
          "difficulty": "\(difficulty.rawValue)",
          "prompt": "Question text for MCQ — null for fill",
          "options": ["word1", "word2", "word3", "word4"],
          "answerIndex": 0,
          "fillPre": "Text before blank — null for MCQ",
          "fillPost": "Text after blank — null for MCQ",
          "verseRef": "Book Chapter:Verse",
          "verseText": "Complete ESV verse text"
        }
        """
    }

    // MARK: - JSON parser

    private func parseQuestions(from jsonString: String,
                                  packId: String,
                                  difficulty: Difficulty) throws -> [TriviaQuestion] {
        guard let data = jsonString.data(using: .utf8) else {
            throw QuestionGeneratorError.parseError("Could not encode JSON string")
        }

        // Gemini occasionally wraps the array in an object — handle both
        if let array = try? JSONDecoder().decode([TriviaQuestion].self, from: data) {
            return array
        }

        // Try unwrapping a top-level object with a "questions" key
        if let obj    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let nested = obj["questions"] as? [[String: Any]],
           let nestedData = try? JSONSerialization.data(withJSONObject: nested),
           let array = try? JSONDecoder().decode([TriviaQuestion].self, from: nestedData) {
            return array
        }

        throw QuestionGeneratorError.parseError("Could not parse questions array from: \(jsonString.prefix(200))")
    }

    // MARK: - Validation

    /// Checks each question against the Ethiopian Bible API.
    /// A question passes if:
    ///   1. The verse ref can be fetched from the API (it exists).
    ///   2. The API verse text and the Gemini verse text share at least 50% of
    ///      words — guards against hallucinated verse text without being too strict
    ///      about ESV vs KJV translation differences.
    private func validate(_ questions: [TriviaQuestion]) async -> [TriviaQuestion] {
        var valid: [TriviaQuestion] = []
        for q in questions {
            if await isValid(q) {
                valid.append(q)
            } else {
                print("[QuestionGeneratorAgent] Rejected (failed validation): \(q.verseRef)")
            }
        }
        return valid
    }

    private func isValid(_ q: TriviaQuestion) async -> Bool {
        // Basic structural checks first
        guard !q.verseRef.isEmpty,
              !q.verseText.isEmpty,
              q.options.count == 4,
              q.answerIndex >= 0,
              q.answerIndex < q.options.count,  // guard against out-of-range crash
              !q.options.contains(where: { $0.isEmpty })
        else { return false }

        // Fill-specific: pre + post must not both be empty
        if q.kind == .fill {
            guard (q.fillPre?.isEmpty == false) || (q.fillPost?.isEmpty == false) else { return false }
        }

        // Fetch from Ethiopian Bible API (English) to verify the verse exists
        guard let apiText = await EthiopianBibleService.shared.verse(
            ref: q.verseRef, language: "en"
        ) else {
            // Verse not found → reject
            return false
        }

        // Loose text similarity: at least 40% word overlap (handles ESV vs KJV diffs)
        let geminiWords = Set(q.verseText.lowercased().components(separatedBy: .whitespacesAndNewlines)
                               .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                               .filter { !$0.isEmpty })
        let apiWords    = Set(apiText.lowercased().components(separatedBy: .whitespacesAndNewlines)
                               .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                               .filter { !$0.isEmpty })

        guard !geminiWords.isEmpty, !apiWords.isEmpty else { return false }
        let overlap = Double(geminiWords.intersection(apiWords).count) / Double(geminiWords.count)
        return overlap >= 0.40
    }

    // MARK: - Disk cache

    private func cacheKey(_ packId: String, _ difficulty: Difficulty) -> String {
        "\(packId)-\(difficulty.rawValue.lowercased())"
    }

    private var cacheDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir  = docs.appendingPathComponent("QuestionCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cacheURL(key: String) -> URL {
        cacheDirectory.appendingPathComponent("\(key).json")
    }

    private func saveCacheToDisk(key: String) {
        guard let questions = cache[key] else { return }
        do {
            let data = try JSONEncoder().encode(questions)
            try data.write(to: cacheURL(key: key), options: .atomic)
        } catch {
            print("[QuestionGeneratorAgent] Failed to save cache '\(key)': \(error)")
        }
    }

    private func loadAllCaches() {
        // Load every *.json file from the cache directory on startup
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: nil
        ) else { return }

        for file in files where file.pathExtension == "json" {
            let key = file.deletingPathExtension().lastPathComponent
            if let data      = try? Data(contentsOf: file),
               let questions = try? JSONDecoder().decode([TriviaQuestion].self, from: data) {
                cache[key] = questions
                print("[QuestionGeneratorAgent] Loaded \(questions.count) cached questions for '\(key)'")
            }
        }
    }

    // MARK: - Pack → book list

    static let packBooks: [String: [String]] = [
        "beginner":  ["John", "Psalms", "Romans", "Philippians", "Matthew", "Isaiah",
                      "Proverbs", "Genesis", "Luke", "Ephesians"],
        "psalms":    ["Psalms"],
        "proverbs":  ["Proverbs"],
        "gospels":   ["Matthew", "Mark", "Luke", "John"],
        "epistles":  ["Romans", "1 Corinthians", "2 Corinthians", "Galatians",
                      "Ephesians", "Philippians", "Colossians",
                      "1 Thessalonians", "2 Thessalonians",
                      "1 Timothy", "2 Timothy", "Titus", "Philemon",
                      "Hebrews", "James", "1 Peter", "2 Peter",
                      "1 John", "2 John", "3 John", "Jude"],
        "ot":        ["Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy",
                      "Joshua", "Judges", "Ruth", "1 Samuel", "2 Samuel",
                      "1 Kings", "2 Kings", "1 Chronicles", "2 Chronicles",
                      "Ezra", "Nehemiah", "Esther", "Job",
                      "Psalms", "Proverbs", "Ecclesiastes", "Song of Solomon",
                      "Isaiah", "Jeremiah", "Lamentations", "Ezekiel", "Daniel",
                      "Hosea", "Joel", "Amos", "Obadiah", "Jonah", "Micah",
                      "Nahum", "Habakkuk", "Zephaniah", "Haggai", "Zechariah", "Malachi"],
    ]
}

// MARK: - Errors

enum QuestionGeneratorError: LocalizedError {
    case parseError(String)
    case validationFailed

    var errorDescription: String? {
        switch self {
        case .parseError(let msg): return "Parse error: \(msg)"
        case .validationFailed:   return "Question failed validation"
        }
    }
}
