import SwiftUI

/// The daily practice card shown at the top of PacksView.
/// Shows one verse from the active pack — lowest mastery first.
/// Tapping "Practice" shows a quick MCQ / fill-in-the-blank.
/// Syncs results to Supabase when the user is signed in.
struct DailyPracticeCard: View {

    let packId: String
    let initialLanguage: String
    let onLanguageChange: ((String) -> Void)?

    @State private var sessionQuestions: [TriviaQuestion] = []
    @State private var sessionIndex = 0
    @State private var sessionCorrectCount = 0
    @State private var question:    TriviaQuestion? = nil
    @State private var practiceTranslation: PracticeTranslation? = nil
    @State private var localizedQuestion: QuizQuestion? = nil
    @State private var localizedVerseText: String? = nil
    @State private var practiceLanguage: String
    @State private var isLoadingLanguage = false
    @State private var languageStatus: String? = nil
    @State private var phase:       Phase = .idle
    @State private var selected:    Int?  = nil
    @State private var isAnimating  = false

    init(
        packId: String,
        initialLanguage: String = "en",
        onLanguageChange: ((String) -> Void)? = nil
    ) {
        self.packId = packId
        self.initialLanguage = initialLanguage
        self.onLanguageChange = onLanguageChange
        _practiceLanguage = State(initialValue: initialLanguage)
    }

    private enum Phase {
        case idle        // not yet started
        case practicing  // showing MCQ / fill
        case result(Bool) // answered — true = correct
        case done        // already practiced today
    }

    private var mastery: Int {
        guard let q = question else { return 0 }
        return VerseMasteryService.shared.masteryLevel(packId: packId, verseRef: q.verseRef)
    }

    private var sessionTotal: Int {
        max(sessionQuestions.count, 1)
    }

    private var stepNumber: Int {
        min(sessionIndex + 1, sessionTotal)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch phase {
            case .idle:
                idleCard
            case .practicing:
                practiceCard
            case .result(let correct):
                resultCard(correct: correct)
            case .done:
                doneCard
            }
        }
        .background(DesignSystem.surface)
        .cornerRadius(18)
        .shadow(color: DesignSystem.shadow1, radius: 8, x: 0, y: 3)
        .onAppear { loadQuestion() }
        .task(id: "\(question?.id ?? "none")-\(practiceLanguage)") {
            await loadLocalizedQuestion()
        }
    }

    // MARK: - Idle card

    private var idleCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(DesignSystem.royalBlue.opacity(0.10))
                    .frame(width: 50, height: 50)
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(DesignSystem.royalBlue)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's practice")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(DesignSystem.royalBlue)
                if let q = question {
                    Text(q.verseRef)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(DesignSystem.ink)
                    Text("\(sessionQuestions.count)-question session")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignSystem.slate400)
                    masteryStars(level: mastery)
                } else {
                    Text("Loading…")
                        .font(.system(size: 14))
                        .foregroundStyle(DesignSystem.slate400)
                }
            }
            Spacer()
            languageMenu
            if question != nil {
                Button {
                    withAnimation(.spring(response: 0.35)) { phase = .practicing }
                } label: {
                    Text("Practice")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(DesignSystem.royalBlue)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    // MARK: - Practice card (MCQ or fill)

    private var practiceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            guard let q = question else { return AnyView(EmptyView()) }
            return AnyView(
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Question \(stepNumber) of \(sessionTotal)")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(1.2)
                                .textCase(.uppercase)
                                .foregroundStyle(DesignSystem.slate400)
                            Text(activeVerseRef(for: q))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(DesignSystem.royalBlue)
                        }
                        Spacer()
                        languageMenu
                        if isLoadingLanguage {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(DesignSystem.royalBlue)
                        }
                        masteryStars(level: mastery)
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(DesignSystem.slate400.opacity(0.18))
                            Capsule()
                                .fill(DesignSystem.royalBlue)
                                .frame(width: proxy.size.width * CGFloat(stepNumber) / CGFloat(sessionTotal))
                        }
                    }
                    .frame(height: 5)

                    // Question text
                    Text(activePrompt(for: q))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DesignSystem.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if let languageStatus {
                        Text(languageStatus)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DesignSystem.slate400)
                    }

                    // Options
                    VStack(spacing: 8) {
                        ForEach(Array(activeOptions(for: q).enumerated()), id: \.offset) { idx, opt in
                            optionButton(idx: idx, text: opt, question: q)
                        }
                    }
                }
                .padding(16)
            )
        }
    }

    private func optionButton(idx: Int, text: String, question: TriviaQuestion) -> some View {
        Button {
            guard selected == nil else { return }
            selected = idx
            let correct = idx == activeAnswerIndex(for: question)
            if correct {
                sessionCorrectCount += 1
            }
            withAnimation(.spring(response: 0.4)) { phase = .result(correct) }
            Task { await VerseMasteryService.shared.recordPractice(
                packId: packId, verseRef: question.verseRef, correct: correct) }
        } label: {
            HStack(spacing: 10) {
                Text(["A","B","C","D"][safe: idx] ?? "")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DesignSystem.slate600)
                    .frame(width: 22)
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(DesignSystem.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(DesignSystem.warmCream)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(DesignSystem.slate400.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Result card

    private func resultCard(correct: Bool) -> some View {
        guard let q = question else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 14) {
                // Result banner
                HStack(spacing: 10) {
                    Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(correct ? DesignSystem.bethanyGreen : DesignSystem.danger)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(correct ? "Well done!" : "Keep going")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DesignSystem.ink)
                        Text("Question \(stepNumber) of \(sessionTotal) · \(q.verseRef)")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignSystem.slate400)
                    }
                    Spacer()
                    masteryStars(level: VerseMasteryService.shared.masteryLevel(
                        packId: packId, verseRef: q.verseRef))
                }

                // Verse text reveal
                Text("\u{201C}\(activeVerseText(for: q))\u{201D}")
                    .font(DesignSystem.serif(14, italic: true))
                    .foregroundStyle(DesignSystem.ink.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .background(DesignSystem.pastoralGold.opacity(0.06))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(DesignSystem.pastoralGold.opacity(0.2), lineWidth: 1))

                Button {
                    continueSession()
                } label: {
                    Text(sessionIndex + 1 < sessionQuestions.count ? "Next question" : "Finish practice")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DesignSystem.royalBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(DesignSystem.royalBlue.opacity(0.08))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        )
    }

    // MARK: - Done card

    private var doneCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(DesignSystem.bethanyGreen.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(DesignSystem.bethanyGreen)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Practice complete")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DesignSystem.ink)
                Text(doneSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.slate400)
            }
            Spacer()
        }
        .padding(16)
    }

    private var doneSubtitle: String {
        guard !sessionQuestions.isEmpty else {
            return "Come back tomorrow for your next practice."
        }
        return "\(sessionCorrectCount) of \(sessionQuestions.count) correct · Come back tomorrow."
    }

    private func continueSession() {
        if sessionIndex + 1 < sessionQuestions.count {
            sessionIndex += 1
            question = sessionQuestions[sessionIndex]
            selected = nil
            clearLocalizedQuestion()
            withAnimation(.spring(response: 0.35)) {
                phase = .practicing
            }
        } else {
            withAnimation {
                phase = .done
            }
        }
    }

    // MARK: - Mastery stars

    private func masteryStars(level: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: i < level ? "star.fill" : "star")
                    .font(.system(size: 9))
                    .foregroundStyle(i < level
                        ? DesignSystem.pastoralGold
                        : DesignSystem.slate400.opacity(0.4))
            }
        }
    }

    private var languageMenu: some View {
        Menu {
            Button { setPracticeLanguage("en") } label: { menuRow("English", code: "en") }
            Button { setPracticeLanguage("am") } label: { menuRow("አማርኛ", code: "am") }
            Button { setPracticeLanguage("or") } label: { menuRow("Afaan Oromoo", code: "or") }
            Button { setPracticeLanguage("ti") } label: { menuRow("ትግርኛ", code: "ti") }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "globe")
                    .font(.system(size: 11, weight: .semibold))
                Text(languageLabel(practiceLanguage))
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(DesignSystem.royalBlue)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(DesignSystem.royalBlue.opacity(0.08))
            .cornerRadius(9)
        }
        .buttonStyle(.plain)
    }

    private func setPracticeLanguage(_ language: String) {
        guard practiceLanguage != language else { return }
        clearLocalizedQuestion()
        selected = nil
        practiceLanguage = language
        onLanguageChange?(language)
    }

    private func clearLocalizedQuestion() {
        localizedQuestion = nil
        practiceTranslation = nil
        localizedVerseText = nil
        languageStatus = nil
    }

    private func menuRow(_ title: String, code: String) -> some View {
        HStack {
            Text(title)
            if practiceLanguage == code {
                Image(systemName: "checkmark")
            }
        }
    }

    private func languageLabel(_ code: String) -> String {
        switch code {
        case "am": return "አማ"
        case "or": return "Oro"
        case "ti": return "ትግ"
        default:   return "EN"
        }
    }

    private func activeVerseRef(for question: TriviaQuestion) -> String {
        if let practiceTranslation { return practiceTranslation.verseRef }
        return localizedQuestion?.verseRef ?? question.verseRef
    }

    private func activePrompt(for question: TriviaQuestion) -> String {
        if let practiceTranslation { return practiceTranslation.prompt }
        return localizedQuestion?.question ?? question.displayPrompt
    }

    private func activeOptions(for question: TriviaQuestion) -> [String] {
        if let practiceTranslation { return practiceTranslation.options }
        if let localizedQuestion {
            return localizedQuestion.options.map(\.text)
        }
        return question.options
    }

    private func activeAnswerIndex(for question: TriviaQuestion) -> Int {
        if let practiceTranslation { return practiceTranslation.answerIndex }
        if let localizedQuestion {
            let letters = ["A", "B", "C", "D"]
            return letters.firstIndex(of: localizedQuestion.correctAnswer) ?? question.answerIndex
        }
        return question.answerIndex
    }

    private func activeVerseText(for question: TriviaQuestion) -> String {
        if let text = practiceTranslation?.verseText, !text.isEmpty {
            return text
        }
        if let localizedVerseText, !localizedVerseText.isEmpty {
            return localizedVerseText
        }
        return question.verseText.isEmpty ? "Open the verse to read the full passage." : question.verseText
    }

    // MARK: - Load question

    private func loadQuestion() {
        let questions = VerseMasteryService.shared.practiceQuestionsForToday(
            packId: packId,
            count: 3
        )
        sessionQuestions = questions
        sessionIndex = 0
        sessionCorrectCount = 0
        question = questions.first
        clearLocalizedQuestion()

        if questions.isEmpty {
            phase = .done
        }
    }

    @MainActor
    private func loadLocalizedQuestion() async {
        guard practiceLanguage != "en", let question else {
            practiceTranslation = nil
            localizedQuestion = nil
            localizedVerseText = nil
            languageStatus = nil
            return
        }
        guard let ref = parseVerseRef(question.verseRef),
              let book = bookAbbreviation(for: ref.bookName) else {
            localizedQuestion = nil
            languageStatus = "Translation unavailable for \(question.verseRef)."
            print("[DailyPracticeCard] Could not parse/resolve ref \(question.verseRef)")
            return
        }

        isLoadingLanguage = true
        languageStatus = "Translating question..."
        print("[DailyPracticeCard] Translating \(question.verseRef) to \(practiceLanguage)")
        defer { isLoadingLanguage = false }

        if let translated = await QuizService.shared.translatePracticeQuestion(
            question: question,
            targetLanguage: practiceLanguage,
            book: book,
            bookName: question.book,
            chapter: ref.chapter,
            verse: ref.verse
        ) {
            practiceTranslation = translated
            localizedQuestion = nil
            localizedVerseText = translated.verseText
            languageStatus = nil
            print("[DailyPracticeCard] Exact translation loaded for \(question.verseRef)")
            return
        }

        print("[DailyPracticeCard] Exact translation failed; trying stored quiz fallback")

        let questions = await QuizService.shared.questions(
            lang: practiceLanguage,
            book: book,
            chapter: ref.chapter,
            verse: ref.verse
        )
        var translatedQuestions = questions
        if bestQuestion(from: translatedQuestions, verse: ref.verse, verseEnd: ref.verseEnd) == nil {
            _ = await QuizService.shared.generateAllLanguages(
                book: book,
                chapter: ref.chapter,
                count: 5
            )
            translatedQuestions = await QuizService.shared.questions(
                lang: practiceLanguage,
                book: book,
                chapter: ref.chapter,
                verse: ref.verse
            )
        }

        localizedQuestion = bestQuestion(from: translatedQuestions, verse: ref.verse, verseEnd: ref.verseEnd)
        localizedVerseText = await EthiopianBibleService.shared.verse(
            ref: question.verseRef,
            language: practiceLanguage
        )
        languageStatus = localizedQuestion == nil
            ? "Translation unavailable. Showing English question."
            : nil
        print("[DailyPracticeCard] Stored fallback \(localizedQuestion == nil ? "missing" : "loaded") for \(question.verseRef)")
    }

    private func bestQuestion(from questions: [QuizQuestion], verse: Int, verseEnd: Int? = nil) -> QuizQuestion? {
        let endVerse = verseEnd ?? verse
        if let exact = questions.first(where: { $0.verseStart == verse && $0.verseEnd == endVerse }) {
            return exact
        }
        if let covering = questions.first(where: {
            guard let start = $0.verseStart, let end = $0.verseEnd else { return false }
            return start <= verse && end >= endVerse
        }) {
            return covering
        }
        return questions.first
    }

    private func parseVerseRef(_ ref: String) -> (bookName: String, chapter: Int, verse: Int, verseEnd: Int?)? {
        let pattern = #"^(.+?)\s+(\d+)[:\.፡](\d+)(?:\s*[-–—]\s*(\d+))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: ref, range: NSRange(ref.startIndex..., in: ref)),
              let bookRange = Range(match.range(at: 1), in: ref),
              let chapterRange = Range(match.range(at: 2), in: ref),
              let verseRange = Range(match.range(at: 3), in: ref),
              let chapter = Int(ref[chapterRange]),
              let verse = Int(ref[verseRange])
        else { return nil }

        var verseEnd: Int? = nil
        if match.range(at: 4).location != NSNotFound,
           let endRange = Range(match.range(at: 4), in: ref) {
            verseEnd = Int(ref[endRange])
        }

        return (String(ref[bookRange]), chapter, verse, verseEnd)
    }

    private func bookAbbreviation(for bookName: String) -> String? {
        let upper = bookName.uppercased()
        if QuestionGeneratorAgent.bookChapterCounts[upper] != nil {
            return upper
        }
        if let abbr = QuestionGeneratorAgent.bookAbbreviations[bookName] {
            return abbr
        }
        if bookName == "Psalm" {
            return QuestionGeneratorAgent.bookAbbreviations["Psalms"]
        }
        return nil
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
