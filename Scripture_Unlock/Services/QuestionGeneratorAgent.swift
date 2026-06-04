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

    /// Directly add pre-validated questions to the cache (used by AITestView
    /// so that test-run results are immediately available for the next alarm).
    func addToCache(_ questions: [TriviaQuestion]) {
        for q in questions {
            let key = cacheKey(q.packId, q.difficulty)
            var slot = cache[key] ?? []
            if !slot.contains(where: { $0.id == q.id || $0.verseRef == q.verseRef }) {
                slot.append(q)
            }
            cache[key] = Array(slot.prefix(maxCacheSize))
            saveCacheToDisk(key: key)
        }
    }

    /// Total number of AI questions ready across all slots.
    var totalCachedCount: Int {
        cache.values.reduce(0) { $0 + $1.count }
    }

    // MARK: - Generation pipeline

    private func generateAndCache(packId: String, difficulty: Difficulty) async {
        let key         = cacheKey(packId, difficulty)
        let existing    = cache[key] ?? []
        let usedRefs    = Set(existing.map(\.verseRef))
        let targetCount = min(batchSize, maxCacheSize - existing.count)
        guard targetCount > 0 else { return }

        print("[QuestionGeneratorAgent] Generating \(targetCount) questions for \(packId)/\(difficulty.rawValue)")

        // ── Priority 1: Centralized Railway API (same backend as study quiz) ──
        let railwayQuestions = await generateViaRailwayAPI(
            packId: packId, difficulty: difficulty,
            count: targetCount, excluding: usedRefs
        )
        if !railwayQuestions.isEmpty {
            await mergeIntoCacheAndSave(railwayQuestions, key: key)
            print("[QuestionGeneratorAgent] Cached \(railwayQuestions.count) Railway questions for \(packId)/\(difficulty.rawValue)")
            return
        }

        // ── Priority 2: On-device Gemini (fallback when Railway is unavailable) ──
        print("[QuestionGeneratorAgent] Railway returned nothing — falling back to on-device Gemini")
        do {
            let prompt     = buildPrompt(packId: packId, difficulty: difficulty,
                                         exclude: usedRefs, count: targetCount)
            let jsonString = try await GeminiService.shared.generate(prompt: prompt)
            let raw        = try parseQuestions(from: jsonString, packId: packId, difficulty: difficulty)
            let validated  = await validate(raw)
            await mergeIntoCacheAndSave(validated, key: key)
            print("[QuestionGeneratorAgent] Cached \(validated.count) Gemini questions for \(packId)/\(difficulty.rawValue)")
        } catch {
            print("[QuestionGeneratorAgent] Both Railway and Gemini failed: \(error.localizedDescription)")
        }
    }

    /// Merge new questions into the cache slot and persist to disk.
    private func mergeIntoCacheAndSave(_ questions: [TriviaQuestion], key: String) async {
        await MainActor.run {
            var slot = self.cache[key] ?? []
            for q in questions {
                if !slot.contains(where: { $0.id == q.id || $0.verseRef == q.verseRef }) {
                    slot.append(q)
                }
            }
            self.cache[key] = Array(slot.prefix(self.maxCacheSize))
            self.saveCacheToDisk(key: key)
        }
    }

    // MARK: - Railway API generation

    /// Calls the centralized Railway API (same backend as the study quiz in Bible Reader).
    /// Makes several calls spread across different books/chapters for the pack.
    private func generateViaRailwayAPI(
        packId: String,
        difficulty: Difficulty,
        count: Int,
        excluding usedRefs: Set<String>
    ) async -> [TriviaQuestion] {
        let books = Self.packBooks[packId] ?? ["Psalms"]
        var results: [TriviaQuestion] = []
        // Each Railway call generates ~5 questions; make enough calls to reach targetCount
        let callsNeeded = max(2, Int(ceil(Double(count) / 5.0)))

        for _ in 0..<callsNeeded {
            guard results.count < count else { break }
            // Pick a random book and chapter from this pack
            guard let bookName = books.randomElement(),
                  let abbr     = Self.bookAbbreviations[bookName],
                  let maxCh    = Self.bookChapterCounts[abbr]
            else { continue }
            let chapter = Int.random(in: 1...maxCh)

            let outcome = await QuizService.shared.generateQuestions(
                book:       abbr,
                chapter:    chapter,
                verseStart: 1, verseEnd: 30,
                language:   "en",
                difficulty: difficulty.railwayValue,
                count:      5,
                save:       true
            )
            guard case .success(let qs) = outcome else { continue }

            let converted = qs.compactMap { convertToTriviaQuestion($0, packId: packId, difficulty: difficulty) }
                              .filter { !usedRefs.contains($0.verseRef) }
            results.append(contentsOf: converted)
        }

        return Array(results.prefix(count))
    }

    /// Converts a Railway `QuizQuestion` (MCQ only) to the app's `TriviaQuestion`.
    /// `verseText` is left empty — `RevealView` fetches it live from the Bible API.
    private func convertToTriviaQuestion(
        _ q: QuizQuestion,
        packId: String,
        difficulty: Difficulty
    ) -> TriviaQuestion? {
        // correctAnswer is a letter "A"/"B"/"C"/"D" — convert to 0-based index
        let letterOrder = ["A", "B", "C", "D"]
        guard let answerIndex = letterOrder.firstIndex(of: q.correctAnswer) else { return nil }
        let options = q.options.map { $0.text }
        guard options.count == 4, !options.contains(where: { $0.isEmpty }) else { return nil }

        // Build a stable id from the verse ref so duplicates are detected across caches
        let safeRef = q.verseRef
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: ".")
        let id = "\(safeRef)-railway-mcq"

        return TriviaQuestion(
            id:         id,
            kind:       .mcq,
            book:       q.bookName,
            packId:     packId,
            difficulty: difficulty,
            prompt:     q.question,
            options:    options,
            answerIndex: answerIndex,
            fillPre:    nil,
            fillPost:   nil,
            verseRef:   q.verseRef,
            verseText:  ""   // fetched lazily by RevealView via EthiopianBibleService
        )
    }

    // MARK: - Book metadata

    /// Maps full English book names (as used in packBooks) to Railway API abbreviations.
    static let bookAbbreviations: [String: String] = [
        // Old Testament
        "Genesis": "GEN", "Exodus": "EXO", "Leviticus": "LEV",
        "Numbers": "NUM", "Deuteronomy": "DEU", "Joshua": "JOS",
        "Judges": "JDG", "Ruth": "RUT", "1 Samuel": "1SA", "2 Samuel": "2SA",
        "1 Kings": "1KI", "2 Kings": "2KI", "1 Chronicles": "1CH", "2 Chronicles": "2CH",
        "Ezra": "EZR", "Nehemiah": "NEH", "Esther": "EST", "Job": "JOB",
        "Psalms": "PSA", "Proverbs": "PRO", "Ecclesiastes": "ECC",
        "Song of Solomon": "SNG", "Isaiah": "ISA", "Jeremiah": "JER",
        "Lamentations": "LAM", "Ezekiel": "EZK", "Daniel": "DAN",
        "Hosea": "HOS", "Joel": "JOL", "Amos": "AMO", "Obadiah": "OBA",
        "Jonah": "JON", "Micah": "MIC", "Nahum": "NAH", "Habakkuk": "HAB",
        "Zephaniah": "ZEP", "Haggai": "HAG", "Zechariah": "ZEC", "Malachi": "MAL",
        // New Testament
        "Matthew": "MAT", "Mark": "MRK", "Luke": "LUK", "John": "JHN",
        "Acts": "ACT", "Romans": "ROM", "1 Corinthians": "1CO", "2 Corinthians": "2CO",
        "Galatians": "GAL", "Ephesians": "EPH", "Philippians": "PHP", "Colossians": "COL",
        "1 Thessalonians": "1TH", "2 Thessalonians": "2TH",
        "1 Timothy": "1TI", "2 Timothy": "2TI", "Titus": "TIT", "Philemon": "PHM",
        "Hebrews": "HEB", "James": "JAS", "1 Peter": "1PE", "2 Peter": "2PE",
        "1 John": "1JN", "2 John": "2JN", "3 John": "3JN", "Jude": "JUD",
    ]

    /// Chapter counts keyed by Railway abbreviation.
    static let bookChapterCounts: [String: Int] = [
        "GEN": 50, "EXO": 40, "LEV": 27, "NUM": 36, "DEU": 34,
        "JOS": 24, "JDG": 21, "RUT": 4,  "1SA": 31, "2SA": 24,
        "1KI": 22, "2KI": 25, "1CH": 29, "2CH": 36, "EZR": 10,
        "NEH": 13, "EST": 10, "JOB": 42, "PSA": 150,"PRO": 31,
        "ECC": 12, "SNG": 8,  "ISA": 66, "JER": 52, "LAM": 5,
        "EZK": 48, "DAN": 12, "HOS": 14, "JOL": 3,  "AMO": 9,
        "OBA": 1,  "JON": 4,  "MIC": 7,  "NAH": 3,  "HAB": 3,
        "ZEP": 3,  "HAG": 2,  "ZEC": 14, "MAL": 4,
        "MAT": 28, "MRK": 16, "LUK": 24, "JHN": 21, "ACT": 28,
        "ROM": 16, "1CO": 16, "2CO": 13, "GAL": 6,  "EPH": 6,
        "PHP": 4,  "COL": 4,  "1TH": 5,  "2TH": 3,  "1TI": 6,
        "2TI": 4,  "TIT": 3,  "PHM": 1,  "HEB": 13, "JAS": 5,
        "1PE": 5,  "2PE": 3,  "1JN": 5,  "2JN": 1,  "3JN": 1, "JUD": 1,
    ]

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

        CRITICAL — every question regardless of type MUST include:
        • "options": exactly 4 non-empty strings (NEVER null or empty array)
        • "answerIndex": integer 0–3 pointing to the correct option (NEVER null)

        For FILL questions specifically:
        • options[answerIndex] is the blanked word
        • fillPre + " " + options[answerIndex] + " " + fillPost reconstructs the verse
        • prompt must be null

        For MCQ questions:
        • fillPre and fillPost must be null
        • prompt must be a non-null question string

        Each item schema:
        {
          "id": "BOOK.CH.VS-kind",
          "kind": "fill" or "mcq",
          "book": "Full book name (e.g. Psalms, John)",
          "packId": "\(packId)",
          "difficulty": "\(difficulty.rawValue)",
          "prompt": null or "Question text?",
          "options": ["word1", "word2", "word3", "word4"],
          "answerIndex": 1,
          "fillPre": "Text before blank" or null,
          "fillPost": "text after blank" or null,
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
