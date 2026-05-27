import SwiftUI

/// Hosts the trivia state machine — routes between MCQ, Fill, Reveal, Dismissed.
struct TriviaContainerView: View {
    let alarm: Alarm
    @State private var vm: TriviaViewModel

    init(alarm: Alarm) {
        self.alarm = alarm
        _vm = State(initialValue: TriviaViewModel(alarm: alarm))
    }

    var body: some View {
        ZStack {
            switch vm.phase {
            case .ringing:
                Color(DesignSystem.warmCream).ignoresSafeArea()
                    .onAppear { vm.begin() }

            case .question:
                questionView
                    .background(DesignSystem.warmCream.ignoresSafeArea())
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))

            case .reveal:
                if let q = vm.currentQuestion {
                    RevealView(question: q, vm: vm)
                        .background(DesignSystem.warmCream.ignoresSafeArea())
                        .transition(.opacity)
                }

            case .dismissed:
                DismissedView(alarm: alarm)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.28), value: vm.phase)
        .onAppear { if vm.phase == .ringing { vm.begin() } }
    }

    @ViewBuilder
    private var questionView: some View {
        if let q = vm.currentQuestion {
            VStack(spacing: 0) {
                TriviaProgressBar(
                    total: vm.totalSteps,
                    completed: vm.completedSteps,
                    ringing: true
                )
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 0)

                if let missed = vm.lastMissedQuestion {
                    MissBanner(missed: missed)
                        .padding(.horizontal, 24)
                        .padding(.top, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                ScrollView {
                    switch q.kind {
                    case .mcq:
                        MCQView(question: q, vm: vm)
                    case .fill:
                        FillView(question: q, vm: vm)
                    }
                }
            }
        }
    }
}

// MARK: - MissBanner

struct MissBanner: View {
    let missed: TriviaQuestion

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(DesignSystem.danger.opacity(0.10))
                    .frame(width: 30, height: 30)
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DesignSystem.danger)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text({
                    var base = AttributedString("Not quite — answer was ")
                    base.swiftUI.font           = .system(size: 13, weight: .bold)
                    base.swiftUI.foregroundColor = DesignSystem.ink
                    var answer = AttributedString(missed.correctAnswer)
                    answer.swiftUI.font           = .system(size: 13, weight: .bold)
                    answer.swiftUI.foregroundColor = DesignSystem.bethanyGreen
                    return base + answer
                }())

                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .bold))
                    Text("New verse · different book")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(DesignSystem.pastoralGold)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.surface)
        .cornerRadius(12)
        .shadow(color: DesignSystem.shadow1, radius: 6, x: 0, y: 2)
    }
}
