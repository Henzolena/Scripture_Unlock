import SwiftUI

/// The daily practice card shown at the top of PacksView.
/// Shows one verse from the active pack — lowest mastery first.
/// Tapping "Practice" shows a quick MCQ / fill-in-the-blank.
/// Syncs results to Supabase when the user is signed in.
struct DailyPracticeCard: View {

    let packId: String

    @State private var question:    TriviaQuestion? = nil
    @State private var phase:       Phase = .idle
    @State private var selected:    Int?  = nil
    @State private var isAnimating  = false

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
                    masteryStars(level: mastery)
                } else {
                    Text("Loading…")
                        .font(.system(size: 14))
                        .foregroundStyle(DesignSystem.slate400)
                }
            }
            Spacer()
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
                        Text(q.verseRef)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(DesignSystem.royalBlue)
                        Spacer()
                        masteryStars(level: mastery)
                    }

                    // Question text
                    Text(q.displayPrompt)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DesignSystem.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    // Options
                    VStack(spacing: 8) {
                        ForEach(Array(q.options.enumerated()), id: \.offset) { idx, opt in
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
            let correct = (idx == question.answerIndex)
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
                        Text(q.verseRef)
                            .font(.system(size: 12))
                            .foregroundStyle(DesignSystem.slate400)
                    }
                    Spacer()
                    masteryStars(level: VerseMasteryService.shared.masteryLevel(
                        packId: packId, verseRef: q.verseRef))
                }

                // Verse text reveal
                Text("\u{201C}\(q.verseText)\u{201D}")
                    .font(DesignSystem.serif(14, italic: true))
                    .foregroundStyle(DesignSystem.ink.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .background(DesignSystem.pastoralGold.opacity(0.06))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(DesignSystem.pastoralGold.opacity(0.2), lineWidth: 1))

                // Done button
                Button {
                    withAnimation { phase = .done }
                } label: {
                    Text("Done for today")
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
                Text("Come back tomorrow for your next verse.")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.slate400)
            }
            Spacer()
        }
        .padding(16)
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

    // MARK: - Load question

    private func loadQuestion() {
        if VerseMasteryService.shared.isPracticedToday(packId: packId,
                                                        verseRef: "") {
            // Will be refined per-verse below
        }
        let q = VerseMasteryService.shared.todaysPracticeQuestion(packId: packId)
        question = q
        if q == nil { return }
        // If already practiced today, skip to done
        if let vr = q?.verseRef,
           VerseMasteryService.shared.isPracticedToday(packId: packId, verseRef: vr) {
            phase = .done
        }
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
