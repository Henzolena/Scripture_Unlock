import SwiftUI

// MARK: - Practice target (sheet item)

struct PracticeTarget: Identifiable {
    let verse:    EthiopianVerse
    let book:     BibleBook
    let language: String
    var id: String { "\(verse.book)-\(verse.chapter)-\(verse.verse)-\(language)" }
}

// MARK: - Main sheet

struct VerseQuizSheet: View {

    let target: PracticeTarget

    @Environment(\.dismiss) private var dismiss

    // MARK: Loading state
    private enum LoadPhase {
        case loading, generating, ready([QuizQuestion]), failed
    }
    @State private var phase: LoadPhase = .loading

    // MARK: Quiz state
    @State private var currentIndex = 0
    @State private var selectedLabel: String?       // which option the user tapped
    @State private var isAnswered    = false
    @State private var score         = 0
    @State private var showFinished  = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.warmCream.ignoresSafeArea()

                switch phase {
                case .loading:
                    loadingView(message: "Finding questions…")

                case .generating:
                    loadingView(message: "Generating questions with AI…")

                case .ready(let questions):
                    if showFinished {
                        finishedView(total: questions.count)
                    } else {
                        quizContent(questions: questions)
                    }

                case .failed:
                    failedView
                }
            }
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(DesignSystem.slate400)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Quiz content

    @ViewBuilder
    private func quizContent(questions: [QuizQuestion]) -> some View {
        let q = questions[currentIndex]

        ScrollView {
            VStack(spacing: 20) {

                // ── Verse card ───────────────────────────────────────────────
                verseCard

                // ── Progress ─────────────────────────────────────────────────
                progressRow(current: currentIndex + 1, total: questions.count, score: score)

                // ── Question card ────────────────────────────────────────────
                questionCard(q)

                // ── Options ──────────────────────────────────────────────────
                VStack(spacing: 10) {
                    ForEach(q.options) { opt in
                        OptionButton(
                            option:        opt,
                            selected:      selectedLabel == opt.label,
                            correctAnswer: isAnswered ? q.correctAnswer : nil,
                            isAnswered:    isAnswered
                        ) {
                            guard !isAnswered else { return }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedLabel = opt.label
                                isAnswered    = true
                                if opt.label == q.correctAnswer { score += 1 }
                            }
                        }
                    }
                }

                // ── Explanation ──────────────────────────────────────────────
                if isAnswered {
                    explanationCard(
                        isCorrect:   selectedLabel == q.correctAnswer,
                        explanation: q.explanation
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))

                    // Next / Finish
                    nextButton(isLast: currentIndex == questions.count - 1) {
                        advance(total: questions.count)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .padding(.bottom, 32)
        }
        .animation(.easeInOut(duration: 0.25), value: isAnswered)
    }

    // MARK: - Verse card

    private var verseCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    "\(target.book.englishName) \(target.verse.chapter):\(target.verse.verse)",
                    systemImage: "book.pages.fill"
                )
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DesignSystem.pastoralGold)
                Spacer()
            }
            Text(target.verse.text)
                .font(DesignSystem.serif(16))
                .foregroundStyle(DesignSystem.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignSystem.pastoralGold.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(DesignSystem.pastoralGold.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Progress row

    private func progressRow(current: Int, total: Int, score: Int) -> some View {
        HStack(spacing: 12) {
            // Dot indicators
            HStack(spacing: 5) {
                ForEach(0..<total, id: \.self) { i in
                    Circle()
                        .fill(i < current - 1 ? DesignSystem.bethanyGreen :
                              i == current - 1 ? DesignSystem.pastoralGold :
                              DesignSystem.slate400.opacity(0.25))
                        .frame(width: i == current - 1 ? 8 : 6,
                               height: i == current - 1 ? 8 : 6)
                        .animation(.spring(response: 0.3), value: current)
                }
            }

            Spacer()

            Text("Q\(current) of \(total)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignSystem.slate400)

            // Score pill
            Text("Score: \(score)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DesignSystem.pastoralGold)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(DesignSystem.pastoralGold.opacity(0.10))
                .clipShape(Capsule())
        }
    }

    // MARK: - Question card

    private func questionCard(_ q: QuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Difficulty badge
            DifficultyBadge(difficulty: q.difficulty)

            Text(q.question)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DesignSystem.ink)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignSystem.surface)
                .shadow(color: DesignSystem.shadow1, radius: 6, x: 0, y: 2)
        )
    }

    // MARK: - Explanation card

    private func explanationCard(isCorrect: Bool, explanation: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(isCorrect ? DesignSystem.bethanyGreen : Color.red)

            VStack(alignment: .leading, spacing: 6) {
                Text(isCorrect ? "Correct!" : "Not quite")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isCorrect ? DesignSystem.bethanyGreen : Color.red)

                if let exp = explanation, !exp.isEmpty {
                    Text(exp)
                        .font(.system(size: 13))
                        .foregroundStyle(DesignSystem.ink.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isCorrect ? DesignSystem.bethanyGreen.opacity(0.08) : Color.red.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isCorrect ? DesignSystem.bethanyGreen.opacity(0.3) : Color.red.opacity(0.25),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Next / Finish button

    private func nextButton(isLast: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(isLast ? "See Results" : "Next Question")
                    .font(.system(size: 16, weight: .bold))
                Image(systemName: isLast ? "chart.bar.fill" : "arrow.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(DesignSystem.deepBlue)
            .cornerRadius(16)
            .shadow(color: DesignSystem.deepBlue.opacity(0.3), radius: 8, x: 0, y: 4)
        }
    }

    // MARK: - Finished screen

    private func finishedView(total: Int) -> some View {
        VStack(spacing: 32) {
            Spacer()

            // Score ring
            ZStack {
                Circle()
                    .stroke(DesignSystem.slate400.opacity(0.15), lineWidth: 12)
                    .frame(width: 160, height: 160)

                Circle()
                    .trim(from: 0, to: CGFloat(score) / CGFloat(max(total, 1)))
                    .stroke(
                        scoreColor(score: score, total: total),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.8, dampingFraction: 0.7), value: score)

                VStack(spacing: 4) {
                    Text("\(score)/\(total)")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundStyle(DesignSystem.ink)
                    Text(scoreLine(score: score, total: total))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignSystem.slate400)
                }
            }

            // Message
            VStack(spacing: 8) {
                Text(scoreTitle(score: score, total: total))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(DesignSystem.ink)
                Text("\(target.book.englishName) \(target.verse.chapter):\(target.verse.verse)")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignSystem.slate400)
            }

            // Actions
            VStack(spacing: 12) {
                Button {
                    withAnimation {
                        currentIndex   = 0
                        selectedLabel  = nil
                        isAnswered     = false
                        score          = 0
                        showFinished   = false
                    }
                } label: {
                    Label("Practice Again", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(DesignSystem.pastoralGold)
                        .cornerRadius(16)
                }

                Button { dismiss() } label: {
                    Text("Close")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DesignSystem.slate600)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(DesignSystem.surface)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(DesignSystem.slate400.opacity(0.2), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
    }

    // MARK: - Loading / failed states

    private func loadingView(message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(DesignSystem.pastoralGold.opacity(0.10))
                    .frame(width: 80, height: 80)
                ProgressView()
                    .scaleEffect(1.3)
                    .tint(DesignSystem.pastoralGold)
            }
            Text(message)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignSystem.slate400)
            Spacer()
        }
    }

    private var failedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(DesignSystem.slate400)
            Text("Couldn't load questions")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(DesignSystem.ink)
            Text("Check your connection and try again.")
                .font(.system(size: 14))
                .foregroundStyle(DesignSystem.slate400)
            Button("Try Again") {
                phase = .loading
                Task { await load() }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(DesignSystem.pastoralGold)
            .padding(.top, 8)
            Spacer()
        }
        .padding(40)
    }

    // MARK: - Navigation helpers

    private func advance(total: Int) {
        if currentIndex < total - 1 {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentIndex  += 1
                selectedLabel  = nil
                isAnswered     = false
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
        let qs = await QuizService.shared.questions(
            lang:    target.language,
            book:    target.book.abbreviation,
            chapter: target.verse.chapter,
            verse:   target.verse.verse
        )

        if !qs.isEmpty {
            withAnimation { phase = .ready(qs) }
            return
        }

        // No static questions — generate with AI
        withAnimation { phase = .generating }
        let generated = await QuizService.shared.generateQuestions(
            book:       target.book.abbreviation,
            chapter:    target.verse.chapter,
            verseStart: target.verse.verse,
            verseEnd:   target.verse.verse,
            language:   target.language,
            count:      5,
            save:       true
        )

        withAnimation {
            phase = generated.isEmpty ? .failed : .ready(generated)
        }
    }

    // MARK: - Score helpers

    private func scoreColor(score: Int, total: Int) -> Color {
        let pct = Double(score) / Double(max(total, 1))
        if pct >= 0.8 { return DesignSystem.bethanyGreen }
        if pct >= 0.5 { return DesignSystem.pastoralGold }
        return Color.red
    }

    private func scoreTitle(score: Int, total: Int) -> String {
        let pct = Double(score) / Double(max(total, 1))
        if pct == 1.0 { return "Perfect! 🎉" }
        if pct >= 0.8 { return "Excellent! 🌟" }
        if pct >= 0.6 { return "Well done! 👍" }
        if pct >= 0.4 { return "Keep going! 💪" }
        return "Keep studying! 📖"
    }

    private func scoreLine(score: Int, total: Int) -> String {
        let pct = Int((Double(score) / Double(max(total, 1))) * 100)
        return "\(pct)% correct"
    }
}

// MARK: - Option button

private struct OptionButton: View {
    let option:        QuizOption
    let selected:      Bool
    let correctAnswer: String?   // non-nil only after answer revealed
    let isAnswered:    Bool
    let action:        () -> Void

    private var state: ButtonState {
        guard isAnswered, let correct = correctAnswer else {
            return selected ? .selected : .idle
        }
        if option.label == correct         { return .correct }
        if selected && option.label != correct { return .wrong }
        return .idle
    }

    private enum ButtonState { case idle, selected, correct, wrong }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Label badge
                ZStack {
                    Circle()
                        .fill(badgeBackground)
                        .frame(width: 32, height: 32)
                    Text(option.label)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(badgeForeground)
                }

                Text(option.text)
                    .font(.system(size: 15, weight: state == .idle ? .regular : .semibold))
                    .foregroundStyle(textColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Result icon
                if isAnswered {
                    resultIcon
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(background)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
        }
        .disabled(isAnswered)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: state)
    }

    @ViewBuilder
    private var resultIcon: some View {
        switch state {
        case .correct:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(DesignSystem.bethanyGreen)
                .font(.system(size: 18))
        case .wrong:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color.red)
                .font(.system(size: 18))
        default:
            EmptyView()
        }
    }

    private var background: Color {
        switch state {
        case .idle:     return DesignSystem.surface
        case .selected: return DesignSystem.pastoralGold.opacity(0.08)
        case .correct:  return DesignSystem.bethanyGreen.opacity(0.08)
        case .wrong:    return Color.red.opacity(0.06)
        }
    }

    private var borderColor: Color {
        switch state {
        case .idle:     return DesignSystem.slate400.opacity(0.15)
        case .selected: return DesignSystem.pastoralGold.opacity(0.5)
        case .correct:  return DesignSystem.bethanyGreen.opacity(0.5)
        case .wrong:    return Color.red.opacity(0.35)
        }
    }

    private var borderWidth: CGFloat { state == .idle ? 1 : 1.5 }

    private var badgeBackground: Color {
        switch state {
        case .idle:     return DesignSystem.pastoralGold.opacity(0.12)
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

private struct DifficultyBadge: View {
    let difficulty: String

    private var color: Color {
        switch difficulty.lowercased() {
        case "beginner":     return DesignSystem.bethanyGreen
        case "intermediate": return DesignSystem.pastoralGold
        case "advanced":     return Color.red
        default:             return DesignSystem.slate400
        }
    }

    private var label: String {
        difficulty.prefix(1).uppercased() + difficulty.dropFirst()
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
