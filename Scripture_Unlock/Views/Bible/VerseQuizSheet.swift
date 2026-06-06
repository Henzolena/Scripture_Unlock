import SwiftUI

// MARK: - Practice target (chapter-level)

struct PracticeTarget: Identifiable {
    let book:     BibleBook
    let chapter:  Int
    let language: String
    var id: String { "\(book.abbreviation)-\(chapter)-\(language)" }
}

// MARK: - Main sheet

struct VerseQuizSheet: View {

    let target: PracticeTarget

    @Environment(\.dismiss) private var dismiss

    // MARK: Load phase
    private enum LoadPhase {
        case loading
        case generating
        case ready([QuizQuestion])
        /// Carries the full structured error so the UI can use icon, title, hint, retryable flag.
        case failed(QuizAPIError)
    }
    @State private var phase: LoadPhase = .loading

    // MARK: Quiz language
    /// Starts at the language the user is currently reading in.
    /// Picker lets them switch to any of the 4 stored languages.
    @State private var quizLanguage: String = ""

    private static let supportedLanguages: [(code: String, flag: String, label: String)] = [
        ("niv", "🇺🇸", "NIV"),
        ("am",  "🇪🇹", "አማ"),
        ("or",  "🇪🇹", "Or"),
        ("ti",  "🇪🇹", "Tig"),
    ]

    private static func quizLanguageCode(for readingLanguage: String) -> String {
        readingLanguage == "en" ? "niv" : readingLanguage
    }

    // MARK: Quiz state
    @State private var currentIndex  = 0
    @State private var selectedLabel: String?
    @State private var isAnswered    = false
    @State private var score         = 0
    @State private var showFinished  = false

    // MARK: Animation state
    @State private var pulseLoading  = false   // drives pulsing rings in loading view
    @State private var shakeOffset: CGFloat = 0
    @State private var feedbackScale = false
    @State private var ringProgress: Double = 0
    @State private var showConfetti  = false

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            DesignSystem.warmCream.ignoresSafeArea()

            VStack(spacing: 0) {
                quizHeader
                contentArea
            }

            if showConfetti {
                ConfettiOverlay()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .task {
            if quizLanguage.isEmpty { quizLanguage = Self.quizLanguageCode(for: target.language) }
            await load()
        }
        .onChange(of: quizLanguage) {
            guard case .ready(let current) = phase else {
                // Not yet loaded — just reload normally
                phase = .loading; currentIndex = 0; selectedLabel = nil
                isAnswered = false; score = 0; showFinished = false
                Task { await load() }
                return
            }
            // Questions already loaded — swap to translated versions of the same questions
            let groupIds = current.compactMap { $0.groupId }
            let newLang  = quizLanguage
            if groupIds.isEmpty {
                // No group_ids (old questions) — fall back to fresh load
                phase = .loading; currentIndex = 0; selectedLabel = nil
                isAnswered = false; score = 0; showFinished = false
                Task { await load() }
            } else {
                Task {
                    withAnimation { phase = .loading }
                    let translated = await QuizService.shared.questionsByGroups(
                        groupIds: groupIds, lang: newLang)
                    withAnimation {
                        if translated.isEmpty {
                            // Language not generated yet — trigger full regeneration
                            phase = .generating
                        } else {
                            // ✅ Same questions, different language — keep current index
                            phase = .ready(translated)
                        }
                    }
                    if case .generating = phase {
                        await load()   // will generate all languages then re-fetch
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var quizHeader: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "0F2744"), Color(hex: "1E3A5F")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 14) {
                HStack(alignment: .center) {
                    // Close button
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Title
                    VStack(spacing: 3) {
                        Text("Practice Quiz")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                        Text("\(target.book.englishName)  ·  Chapter \(target.chapter)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }

                    Spacer()

                    // Live score badge — visible only while actively quizzing
                    if case .ready = phase, !showFinished {
                        VStack(spacing: 1) {
                            Text("\(score)")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundStyle(DesignSystem.pastoralGold)
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.3), value: score)
                            Text("pts")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.4))
                        }
                        .frame(width: 38)
                    } else {
                        Color.clear.frame(width: 38, height: 38)
                    }
                }

                // Language switcher — always visible
                languagePicker

                // Progress bar — only during the quiz
                if case .ready(let qs) = phase, !showFinished {
                    quizProgressBar(current: currentIndex, total: qs.count)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // Language picker strip
    private var languagePicker: some View {
        HStack(spacing: 6) {
            ForEach(Self.supportedLanguages, id: \.code) { lang in
                Button {
                    guard lang.code != quizLanguage else { return }
                    withAnimation(.spring(response: 0.3)) { quizLanguage = lang.code }
                } label: {
                    HStack(spacing: 4) {
                        Text(lang.flag).font(.system(size: 11))
                        Text(lang.label)
                            .font(.system(size: 11, weight: quizLanguage == lang.code ? .bold : .regular))
                    }
                    .foregroundStyle(quizLanguage == lang.code ? DesignSystem.pastoralGold : .white.opacity(0.45))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(quizLanguage == lang.code
                                ? DesignSystem.pastoralGold.opacity(0.18)
                                : Color.white.opacity(0.06))
                    )
                    .overlay(
                        Capsule()
                            .stroke(quizLanguage == lang.code
                                ? DesignSystem.pastoralGold.opacity(0.5)
                                : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // Animated linear progress bar
    private func quizProgressBar(current: Int, total: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 5)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "E5C684"), DesignSystem.pastoralGold],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(
                        width: total > 0
                            ? geo.size.width * CGFloat(current) / CGFloat(total)
                            : 0,
                        height: 5
                    )
                    .animation(.spring(response: 0.55, dampingFraction: 0.8), value: current)
            }
        }
        .frame(height: 5)
    }

    // MARK: - Content area switcher

    @ViewBuilder
    private var contentArea: some View {
        switch phase {
        case .loading:
            centeredState { loadingView(icon: "book.closed.fill", message: "Finding questions…") }

        case .generating:
            centeredState { generatingView }

        case .ready(let qs):
            if showFinished {
                finishedView(total: qs.count)
            } else {
                quizBody(questions: qs)
            }

        case .failed(let err):
            centeredState { failedView(err) }
        }
    }

    // Wraps loading/error states so they fill the remaining space
    private func centeredState<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack {
            Spacer()
            content()
            Spacer()
        }
    }

    // MARK: - Quiz body

    private func quizBody(questions: [QuizQuestion]) -> some View {
        let q = questions[currentIndex]

        return ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {

                    // Question counter row
                    HStack {
                        Text("Question \(currentIndex + 1) of \(questions.count)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DesignSystem.slate400)
                        Spacer()
                        QuizDifficultyBadge(difficulty: q.difficulty)
                    }
                    .padding(.top, 22)
                    .id("scroll-top")

                    // ── Question card + options — animated as a unit when index changes ──
                    VStack(spacing: 12) {
                        questionCard(q)

                        VStack(spacing: 10) {
                            ForEach(q.options) { opt in
                                QuizOptionButton(
                                    option:        opt,
                                    selected:      selectedLabel == opt.label,
                                    correctAnswer: isAnswered ? q.correctAnswer : nil,
                                    isAnswered:    isAnswered
                                ) {
                                    guard !isAnswered else { return }
                                    handleTap(option: opt, correct: q.correctAnswer)
                                }
                            }
                        }
                        .offset(x: shakeOffset)
                    }
                    .id("question-\(currentIndex)")
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal:   .move(edge: .leading).combined(with: .opacity)
                    ))

                    // ── Explanation + Next — appear in-place after answering ──
                    if isAnswered {
                        explanationCard(
                            isCorrect:   selectedLabel == q.correctAnswer,
                            explanation: q.explanation
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))

                        nextButton(isLast: currentIndex == questions.count - 1) {
                            advance(total: questions.count)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 32)
                    }
                }
                .padding(.horizontal, 20)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: currentIndex)
                .animation(.easeOut(duration: 0.28), value: isAnswered)
            }
            .onChange(of: currentIndex) { _, _ in
                withAnimation { proxy.scrollTo("scroll-top", anchor: .top) }
            }
        }
    }

    // MARK: - Question card

    private func questionCard(_ q: QuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Gold accent strip
            LinearGradient(
                colors: [DesignSystem.pastoralGold.opacity(0.6), DesignSystem.pastoralGold],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 3)

            VStack(alignment: .leading, spacing: 14) {
                // Verse reference chip
                Label(q.verseRef, systemImage: "book.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DesignSystem.pastoralGold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DesignSystem.pastoralGold.opacity(0.10))
                    .clipShape(Capsule())

                Text(q.question)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DesignSystem.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: DesignSystem.shadow1, radius: 12, x: 0, y: 4)
    }

    // MARK: - Explanation card

    private func explanationCard(isCorrect: Bool, explanation: String?) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(isCorrect ? DesignSystem.bethanyGreen : Color.red)
                    .frame(width: 40, height: 40)
                Image(systemName: isCorrect ? "checkmark" : "xmark")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(.white)
            }
            .scaleEffect(feedbackScale ? 1.2 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.45), value: feedbackScale)
            .onAppear {
                feedbackScale = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    feedbackScale = false
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(isCorrect ? "Correct!" : "Not quite")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isCorrect ? DesignSystem.bethanyGreen : Color.red)

                if let exp = explanation, !exp.isEmpty {
                    Text(exp)
                        .font(.system(size: 14))
                        .foregroundStyle(DesignSystem.slate600)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(3)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(isCorrect ? DesignSystem.bethanyGreen.opacity(0.07) : Color.red.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(
                            isCorrect
                                ? DesignSystem.bethanyGreen.opacity(0.30)
                                : Color.red.opacity(0.25),
                            lineWidth: 1.5
                        )
                )
        )
    }

    // MARK: - Next / Finish button

    private func nextButton(isLast: Bool, action: @escaping () -> Void) -> some View {
        AppActionButton(
            title: isLast ? "See Results" : "Next Question",
            icon: isLast ? "trophy.fill" : "arrow.right",
            action: action
        )
    }

    // MARK: - Finished / Results screen

    private func finishedView(total: Int) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                Spacer().frame(height: 24)

                // Animated score ring
                ZStack {
                    Circle()
                        .stroke(DesignSystem.slate400.opacity(0.12), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: ringProgress)
                        .stroke(
                            scoreGradient(score: score, total: total),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(
                            .spring(response: 1.1, dampingFraction: 0.72).delay(0.15),
                            value: ringProgress
                        )

                    VStack(spacing: 4) {
                        Text("\(score)")
                            .font(.system(size: 54, weight: .black, design: .rounded))
                            .foregroundStyle(DesignSystem.ink)
                            .contentTransition(.numericText())
                        Text("out of \(total)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DesignSystem.slate400)
                    }
                }
                .frame(width: 186, height: 186)

                // Title + subtitle
                VStack(spacing: 10) {
                    Text(scoreTitle(score: score, total: total))
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(DesignSystem.ink)
                        .multilineTextAlignment(.center)

                    Text("\(Int((Double(score) / Double(max(total, 1))) * 100))% accuracy")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DesignSystem.slate400)

                    Text("\(target.book.englishName)  ·  Chapter \(target.chapter)")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignSystem.slate400.opacity(0.65))
                }

                // Stat pills
                HStack(spacing: 12) {
                    statPill(
                        value: "\(score)",
                        label: "Correct",
                        color: DesignSystem.bethanyGreen
                    )
                    statPill(
                        value: "\(total - score)",
                        label: "Missed",
                        color: Color.red
                    )
                    statPill(
                        value: "\(Int((Double(score) / Double(max(total, 1))) * 100))%",
                        label: "Accuracy",
                        color: DesignSystem.pastoralGold
                    )
                }

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                            currentIndex  = 0
                            selectedLabel = nil
                            isAnswered    = false
                            score         = 0
                            showFinished  = false
                            ringProgress  = 0
                            showConfetti  = false
                        }
                    } label: {
                        AppActionLabel(
                            title: "Practice Again",
                            icon: "arrow.counterclockwise",
                            style: .gold
                        )
                    }
                    .buttonStyle(.plain)

                    AppActionButton(title: "Close", style: .neutral) {
                        dismiss()
                    }
                }
                .padding(.top, 4)

                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            withAnimation {
                ringProgress = Double(score) / Double(max(total, 1))
            }
            let pct = Double(score) / Double(max(total, 1))
            if pct >= 0.7 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showConfetti = true
                }
            }
        }
    }

    // MARK: - Stat pill

    private func statPill(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignSystem.slate400)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(color.opacity(0.22), lineWidth: 1)
                )
        )
    }

    // MARK: - Loading view

    private func loadingView(icon: String, message: String) -> some View {
        VStack(spacing: 28) {
            ZStack {
                // Pulsing rings
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(DesignSystem.pastoralGold.opacity(0.12 - Double(i) * 0.035))
                        .frame(
                            width:  70 + CGFloat(i) * 22,
                            height: 70 + CGFloat(i) * 22
                        )
                        .scaleEffect(pulseLoading ? 1.0 : 0.80)
                        .animation(
                            .easeInOut(duration: 1.3)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.18),
                            value: pulseLoading
                        )
                }
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundStyle(DesignSystem.pastoralGold)
            }
            .frame(width: 120, height: 120)

            Text(message)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignSystem.slate400)
        }
        .onAppear { pulseLoading = true }
        .onDisappear { pulseLoading = false }
    }

    // MARK: - Generating view

    private var generatingView: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(DesignSystem.deepBlue.opacity(0.07))
                    .frame(width: 90, height: 90)
                Image(systemName: "sparkles")
                    .font(.system(size: 34))
                    .foregroundStyle(DesignSystem.pastoralGold)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            }

            VStack(spacing: 8) {
                Text("Crafting your questions…")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DesignSystem.ink)
                Text("Building fresh questions for this chapter")
                    .font(.system(size: 13))
                    .foregroundStyle(DesignSystem.slate400)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Bouncing dots
            BouncingDots()
        }
    }

    // MARK: - Failed view

    private func failedView(_ err: QuizAPIError) -> some View {
        // Tint: gold for transient AI issues, slate for config, red for network/unknown
        let tint: Color = {
            switch err.errorCode {
            // Transient AI issues — gold (calm, retryable)
            case "AI_RATE_LIMITED",  "AI_TIMEOUT",
                 "AI_SERVER_ERROR",  "AI_UNAVAILABLE",
                 "GEMINI_RATE_LIMITED", "GEMINI_TIMEOUT",
                 "SERVER_ERROR",     "SERVER_UNAVAILABLE": return DesignSystem.pastoralGold
            // Config / auth issues — slate (informational)
            case "AI_NOT_CONFIGURED", "AI_UNAUTHORIZED",
                 "GEMINI_NOT_CONFIGURED":                   return DesignSystem.slate400
            // Network / unknown — red
            default:                                        return Color.red
            }
        }()

        return VStack(spacing: 22) {

            // Icon circle
            ZStack {
                Circle()
                    .fill(tint.opacity(0.10))
                    .frame(width: 84, height: 84)
                Image(systemName: err.iconName)
                    .font(.system(size: 32))
                    .foregroundStyle(tint.opacity(0.85))
            }

            // Title + message
            VStack(spacing: 8) {
                Text(err.friendlyTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DesignSystem.ink)
                Text(err.message)
                    .font(.system(size: 14))
                    .foregroundStyle(DesignSystem.slate600)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Hint bubble
            if let hint = err.hint, !hint.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignSystem.pastoralGold)
                    Text(hint)
                        .font(.system(size: 13))
                        .foregroundStyle(DesignSystem.slate600)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(DesignSystem.pastoralGold.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(DesignSystem.pastoralGold.opacity(0.25), lineWidth: 1)
                        )
                )
            }

            // Try Again — always shown; label adapts to error type
            Button {
                phase = .loading
                Task { await load() }
            } label: {
                Label(
                    err.isRetryable ? "Try Again" : "Retry",
                    systemImage: err.errorCode == "GEMINI_RATE_LIMITED"
                        ? "clock.arrow.circlepath"
                        : "arrow.clockwise"
                )
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 30)
                .padding(.vertical, 14)
                .background(tint)
                .clipShape(Capsule())
            }
            .buttonStyle(QuizScaleButtonStyle())
        }
        .padding(.horizontal, 36)
    }

    // MARK: - Interaction

    private func handleTap(option: QuizOption, correct: String) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        selectedLabel = option.label
        isAnswered    = true

        if option.label == correct {
            score += 1
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            // Horizontal shake
            let spring = Animation.interpolatingSpring(stiffness: 700, damping: 12)
            withAnimation(spring) { shakeOffset = 12 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                withAnimation(spring) { shakeOffset = -12 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(spring) { shakeOffset = 7 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(spring) { shakeOffset = 0 }
            }
        }
    }

    private func advance(total: Int) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if currentIndex < total - 1 {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                currentIndex  += 1
                selectedLabel  = nil
                isAnswered     = false
                shakeOffset    = 0
                feedbackScale  = false
            }
        } else {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showFinished = true
            }
        }
    }

    // MARK: - Data loading

    private func load() async {
        phase = .loading
        let lang = quizLanguage.isEmpty ? target.language : quizLanguage

        // 1. Try stored questions first (instant — no AI call needed)
        let stored = await QuizService.shared.chapterQuestions(
            lang:    lang,
            book:    target.book.abbreviation,
            chapter: target.chapter
        )
        if !stored.isEmpty, stored.allSatisfy({ $0.groupId != nil }) {
            withAnimation { phase = .ready(stored) }
            return
        }

        // 2. Nothing stored → generate ALL languages at once (EN + AM + OR + TI)
        withAnimation { phase = .generating }
        let counts = await QuizService.shared.generateAllLanguages(
            book:    target.book.abbreviation,
            chapter: target.chapter,
            count:   5
        )

        // If all-language generation succeeded, fetch the requested language
        if let cnt = counts[lang], cnt > 0 {
            let qs = await QuizService.shared.chapterQuestions(
                lang: lang, book: target.book.abbreviation, chapter: target.chapter)
            withAnimation { phase = qs.isEmpty ? .failed(QuizAPIError(errorCode: "EMPTY_RESPONSE", message: "No questions generated.", hint: nil)) : .ready(qs) }
            return
        }

        withAnimation {
            phase = .failed(QuizAPIError(
                errorCode: "MULTILINGUAL_GENERATION_FAILED",
                message:   "No synced quiz set could be generated for this chapter.",
                hint:      "Try again in a moment. The quiz needs one linked set so language switching stays on the same questions."
            ))
        }
    }

    // MARK: - Score helpers

    private func scoreGradient(score: Int, total: Int) -> LinearGradient {
        let pct = Double(score) / Double(max(total, 1))
        let colors: [Color] = pct >= 0.8
            ? [DesignSystem.bethanyGreen, Color(hex: "34D399")]
            : pct >= 0.5
            ? [DesignSystem.pastoralGold, Color(hex: "FCD34D")]
            : [Color.red, Color(hex: "F87171")]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func scoreTitle(score: Int, total: Int) -> String {
        let pct = Double(score) / Double(max(total, 1))
        if pct == 1.0 { return "Perfect Score! 🎉" }
        if pct >= 0.8 { return "Excellent! 🌟" }
        if pct >= 0.6 { return "Well Done! 👍" }
        if pct >= 0.4 { return "Keep Going! 💪" }
        return "Keep Studying! 📖"
    }
}

// MARK: - Quiz Option Button

private struct QuizOptionButton: View {

    let option:        QuizOption
    let selected:      Bool
    let correctAnswer: String?
    let isAnswered:    Bool
    let action:        () -> Void

    private enum OptionState { case idle, selected, correct, wrong }

    private var state: OptionState {
        guard isAnswered, let correct = correctAnswer else {
            return selected ? .selected : .idle
        }
        if option.label == correct              { return .correct }
        if selected && option.label != correct  { return .wrong }
        return .idle
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Label badge — rounded square
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(badgeBackground)
                        .frame(width: 38, height: 38)
                    Text(option.label)
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(badgeForeground)
                }

                Text(option.text)
                    .font(.system(size: 15, weight: state == .idle ? .regular : .semibold))
                    .foregroundStyle(textColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(2)

                if isAnswered { resultIcon }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 17))
            .overlay(
                RoundedRectangle(cornerRadius: 17)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
        }
        .disabled(isAnswered)
        .buttonStyle(QuizScaleButtonStyle())
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: state)
    }

    @ViewBuilder
    private var resultIcon: some View {
        switch state {
        case .correct:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(DesignSystem.bethanyGreen)
        case .wrong:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.red)
        default:
            EmptyView()
        }
    }

    private var background: Color {
        switch state {
        case .idle:     return DesignSystem.surface
        case .selected: return DesignSystem.pastoralGold.opacity(0.07)
        case .correct:  return DesignSystem.bethanyGreen.opacity(0.08)
        case .wrong:    return Color.red.opacity(0.06)
        }
    }

    private var borderColor: Color {
        switch state {
        case .idle:     return DesignSystem.slate400.opacity(0.14)
        case .selected: return DesignSystem.pastoralGold.opacity(0.55)
        case .correct:  return DesignSystem.bethanyGreen.opacity(0.5)
        case .wrong:    return Color.red.opacity(0.38)
        }
    }

    private var borderWidth: CGFloat { state == .idle ? 1 : 1.5 }

    private var badgeBackground: Color {
        switch state {
        case .idle:     return DesignSystem.pastoralGold.opacity(0.11)
        case .selected: return DesignSystem.pastoralGold
        case .correct:  return DesignSystem.bethanyGreen
        case .wrong:    return Color.red
        }
    }

    private var badgeForeground: Color {
        switch state {
        case .idle: return DesignSystem.pastoralGold
        default:    return .white
        }
    }

    private var textColor: Color {
        switch state {
        case .correct: return DesignSystem.bethanyGreen
        case .wrong:   return Color.red
        default:       return DesignSystem.ink
        }
    }
}

// MARK: - Difficulty badge

private struct QuizDifficultyBadge: View {

    let difficulty: String

    private var color: Color {
        switch difficulty.lowercased() {
        case "beginner":     return DesignSystem.bethanyGreen
        case "intermediate": return DesignSystem.pastoralGold
        case "advanced":     return Color.red
        default:             return DesignSystem.slate400
        }
    }

    var body: some View {
        Text(difficulty.prefix(1).uppercased() + difficulty.dropFirst())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Bouncing dots (generating state)

private struct BouncingDots: View {

    @State private var bounce = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(DesignSystem.pastoralGold)
                    .frame(width: 9, height: 9)
                    .offset(y: bounce ? -8 : 0)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.16),
                        value: bounce
                    )
            }
        }
        .onAppear { bounce = true }
        .onDisappear { bounce = false }
    }
}

// MARK: - Scale button style (shared)

private struct QuizScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - Confetti overlay

private struct ConfettiOverlay: View {

    struct Piece: Identifiable {
        let id    = UUID()
        let x:    CGFloat
        let rot:  Double       // target rotation
        let size: CGFloat
        let color: Color
        let delay: Double
        let dur:  Double
    }

    @State private var pieces: [Piece] = []
    @State private var active = false

    private let palette: [Color] = [
        Color(hex: "C9A961"), Color(hex: "059669"),
        Color(hex: "F472B6"), Color(hex: "60A5FA"),
        Color(hex: "A78BFA"), Color(hex: "FB923C")
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { p in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(p.color)
                        .frame(width: p.size, height: p.size * 0.5)
                        .rotationEffect(.degrees(active ? p.rot : 0))
                        .position(
                            x: p.x,
                            y: active ? geo.size.height + 130 : -70
                        )
                        .animation(
                            .easeIn(duration: p.dur).delay(p.delay),
                            value: active
                        )
                }
            }
            .onAppear {
                let w = geo.size.width
                pieces = (0..<65).map { i in
                    Piece(
                        x:     CGFloat.random(in: 10...(w - 10)),
                        rot:   Double.random(in: 200...720),
                        size:  CGFloat.random(in: 6...15),
                        color: palette[i % palette.count],
                        delay: Double(i % 22) * 0.038,
                        dur:   Double.random(in: 1.6...2.6)
                    )
                }
                // Brief delay so pieces are rendered before animating
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    active = true
                }
            }
        }
    }
}
