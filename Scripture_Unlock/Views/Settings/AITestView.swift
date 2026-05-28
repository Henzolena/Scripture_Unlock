import SwiftUI

/// Developer screen for testing the Gemini question generator end-to-end.
/// Accessible via Settings → Developer → "Test AI question generator".
struct AITestView: View {

    // MARK: - State

    @State private var selectedPack:       VersePack  = .psalms
    @State private var selectedDifficulty: Difficulty = .gentle
    @State private var isGenerating = false
    @State private var results: [TestResult] = []
    @State private var errorMessage: String? = nil
    @State private var elapsedSeconds: Double = 0
    @State private var startTime: Date?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // ── Config ────────────────────────────────────────────────
                Section("Config") {
                    Picker("Pack", selection: $selectedPack) {
                        ForEach(VersePack.all, id: \.id) { p in
                            Text(p.name).tag(p)
                        }
                    }
                    Picker("Difficulty", selection: $selectedDifficulty) {
                        ForEach(Difficulty.allCases, id: \.self) { d in
                            Text(d.rawValue).tag(d)
                        }
                    }
                }

                // ── API key status ────────────────────────────────────────
                Section("API key") {
                    let key = GeminiService.shared.apiKey
                    HStack {
                        Image(systemName: key.isEmpty ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(key.isEmpty ? .red : .green)
                        Text(key.isEmpty
                             ? "Missing — add GEMINI_API_KEY to Secrets.xcconfig"
                             : "Configured (\(key.prefix(8))…)")
                            .font(.system(size: 13))
                            .foregroundStyle(key.isEmpty ? .red : .primary)
                    }
                }

                // ── Run button ────────────────────────────────────────────
                Section {
                    Button {
                        runTest()
                    } label: {
                        HStack {
                            if isGenerating {
                                ProgressView().scaleEffect(0.8)
                                Text("Generating…  (\(String(format: "%.1f", elapsedSeconds))s)")
                            } else {
                                Image(systemName: "bolt.fill")
                                Text("Generate 5 questions now")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isGenerating || GeminiService.shared.apiKey.isEmpty)
                    .tint(DesignSystem.royalBlue)
                }

                // ── Error ─────────────────────────────────────────────────
                if let err = errorMessage {
                    Section("Error") {
                        Text(err)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                }

                // ── Results ───────────────────────────────────────────────
                if !results.isEmpty {
                    Section("Results — \(results.filter(\.passed).count)/\(results.count) passed validation") {
                        ForEach(results) { r in
                            ResultRow(result: r)
                        }
                    }
                }

                // ── Cache status ──────────────────────────────────────────
                Section("Cache status") {
                    ForEach(VersePack.all, id: \.id) { pack in
                        ForEach(Difficulty.allCases, id: \.self) { diff in
                            let count = QuestionGeneratorAgent.shared
                                .questions(forPack: pack.id, difficulty: diff).count
                            if count > 0 {
                                HStack {
                                    Text("\(pack.name) / \(diff.rawValue)")
                                        .font(.system(size: 13))
                                    Spacer()
                                    Text("\(count) ready")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(count >= 10 ? .green : .orange)
                                }
                            }
                        }
                    }
                    if VersePack.all.allSatisfy({ pack in
                        Difficulty.allCases.allSatisfy {
                            QuestionGeneratorAgent.shared.questions(forPack: pack.id, difficulty: $0).isEmpty
                        }
                    }) {
                        Text("Cache is empty — tap Generate to fill it")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("AI Question Tester")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Test logic

    private func runTest() {
        isGenerating  = true
        errorMessage  = nil
        results       = []
        startTime     = Date()
        elapsedSeconds = 0

        // Tick timer
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { t in
            elapsedSeconds = Date().timeIntervalSince(startTime ?? Date())
            if !isGenerating { t.invalidate() }
        }

        let pack = selectedPack
        let diff = selectedDifficulty

        Task {
            do {
                // Build a small test prompt (5 questions only to keep it fast)
                let prompt = buildTestPrompt(pack: pack, difficulty: diff, count: 5)
                let jsonString = try await GeminiService.shared.generate(prompt: prompt)

                // Parse
                guard let data  = jsonString.data(using: .utf8),
                      let raw   = try? JSONDecoder().decode([TriviaQuestion].self, from: data)
                else {
                    throw NSError(domain: "AITest", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey:
                                    "Could not parse JSON. Raw response:\n\(jsonString.prefix(500))"])
                }

                // Validate each one and build results
                var testResults: [TestResult] = []
                for q in raw {
                    let apiText = await EthiopianBibleService.shared.verse(
                        ref: q.verseRef, language: "en"
                    )
                    let overlap = wordOverlap(q.verseText, apiText ?? "")
                    testResults.append(TestResult(
                        question:  q,
                        apiText:   apiText,
                        overlap:   overlap,
                        passed:    apiText != nil && overlap >= 0.40
                    ))
                }

                await MainActor.run {
                    results       = testResults
                    isGenerating  = false
                    timer.invalidate()
                }

            } catch {
                await MainActor.run {
                    errorMessage  = error.localizedDescription
                    isGenerating  = false
                    timer.invalidate()
                }
            }
        }
    }

    private func buildTestPrompt(pack: VersePack, difficulty: Difficulty, count: Int) -> String {
        let books = QuestionGeneratorAgent.packBooks[pack.id]?.prefix(5).joined(separator: ", ")
                    ?? pack.name
        return """
        Generate exactly \(count) Bible trivia questions from \(pack.name) (\(books)).
        Difficulty: \(difficulty.rawValue).
        Mix fill-in-the-blank and MCQ types.
        Use real, accurate ESV verse text.
        Return ONLY a JSON array. Each item: {"id":"BOOK.CH.VS-kind","kind":"fill" or "mcq","book":"Full name","packId":"\(pack.id)","difficulty":"\(difficulty.rawValue)","prompt":null or "question text","options":["a","b","c","d"],"answerIndex":0,"fillPre":null or "text","fillPost":null or "text","verseRef":"Book CH:VS","verseText":"full verse"}
        """
    }

    private func wordOverlap(_ a: String, _ b: String) -> Double {
        func words(_ s: String) -> Set<String> {
            Set(s.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { !$0.isEmpty })
        }
        let wa = words(a), wb = words(b)
        guard !wa.isEmpty else { return 0 }
        return Double(wa.intersection(wb).count) / Double(wa.count)
    }
}

// MARK: - Result row

private struct ResultRow: View {
    let result: TestResult

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.passed ? .green : .red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.question.verseRef)
                        .font(.system(size: 13, weight: .semibold))
                    Text("[\(result.question.kind.rawValue.uppercased())] · \(Int(result.overlap * 100))% word match")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if expanded {
                Divider()

                Group {
                    if result.question.kind == .fill {
                        Text("Blank: \(result.question.fillPre ?? "") ___ \(result.question.fillPost ?? "")")
                            .font(.system(size: 12, design: .monospaced))
                        Text("Answer: \(result.question.correctAnswer)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.green)
                    } else {
                        Text(result.question.prompt ?? "")
                            .font(.system(size: 12, design: .monospaced))
                        ForEach(Array(result.question.options.enumerated()), id: \.offset) { i, opt in
                            HStack(spacing: 4) {
                                Text(i == result.question.answerIndex ? "✓" : "·")
                                    .foregroundStyle(i == result.question.answerIndex ? .green : .secondary)
                                Text(opt).font(.system(size: 12))
                            }
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 3) {
                    Text("Gemini verse:")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    Text(result.question.verseText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(result.passed ? .primary : .red)

                    if let api = result.apiText {
                        Text("API verse:")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                            .padding(.top, 2)
                        Text(api)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("⚠️ Verse not found in Ethiopian Bible API")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
        }
    }
}

// MARK: - Model

private struct TestResult: Identifiable {
    let id        = UUID()
    let question:  TriviaQuestion
    let apiText:   String?
    let overlap:   Double
    let passed:    Bool
}
