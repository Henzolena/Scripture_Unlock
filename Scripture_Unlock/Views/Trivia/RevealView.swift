import SwiftUI
import SwiftData

/// Shown after a correct answer — highlights the right option, reveals the full verse.
/// When the user has selected a parallel language in Settings, the verse card also shows
/// that translation fetched from the Ethiopian Bible API.
struct RevealView: View {
    let question: TriviaQuestion
    @Bindable var vm: TriviaViewModel
    @Query private var profiles: [UserProfile]

    @State private var parallelText: String? = nil

    private var parallelLanguage: String {
        profiles.first?.parallelLanguage ?? ""
    }
    private var langInfo: EthiopianBibleService.LanguageInfo? {
        EthiopianBibleService.info(for: parallelLanguage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TriviaProgressBar(total: vm.totalSteps, completed: vm.completedSteps, ringing: true)
                .padding(.horizontal, 24)
                .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "book.fill").font(.system(size: 12)).foregroundStyle(DesignSystem.pastoralGold)
                        Text(question.book.uppercased())
                            .font(.system(size: 11, weight: .bold)).tracking(2)
                            .foregroundStyle(DesignSystem.pastoralGold)
                    }
                    .padding(.horizontal, 24).padding(.top, 28)

                    Text(question.displayPrompt)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(DesignSystem.ink)
                        .padding(.horizontal, 24).padding(.top, 14)

                    VStack(spacing: 10) {
                        ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                            let correct = index == question.answerIndex
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(correct ? DesignSystem.bethanyGreen : Color.primary.opacity(0.06))
                                        .frame(width: 34, height: 34)
                                    if correct {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(.white)
                                    } else {
                                        Text(String(UnicodeScalar(65 + index)!))
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(DesignSystem.slate600)
                                    }
                                }
                                Text(option)
                                    .font(.system(size: 16, weight: correct ? .bold : .medium))
                                    .foregroundStyle(DesignSystem.ink)
                                Spacer()
                                if correct {
                                    Text("CORRECT")
                                        .font(.system(size: 10, weight: .bold)).tracking(1.5)
                                        .foregroundStyle(DesignSystem.bethanyGreen)
                                }
                            }
                            .padding(.leading, 12).padding(.trailing, 18)
                            .frame(minHeight: 60)
                            .background(correct ? DesignSystem.bethanyGreen.opacity(0.10) : DesignSystem.surface)
                            .cornerRadius(16)
                            .overlay(RoundedRectangle(cornerRadius: 16)
                                .stroke(correct ? DesignSystem.bethanyGreen.opacity(0.5) : Color.clear, lineWidth: 1.5))
                            .shadow(color: correct ? .clear : DesignSystem.shadow1, radius: 6, x: 0, y: 2)
                            .opacity(correct ? 1.0 : 0.45)
                        }
                    }
                    .padding(.horizontal, 24).padding(.top, 20)

                    // ── Verse card ────────────────────────────────────────
                    verseCard
                        .padding(.horizontal, 24).padding(.top, 18)

                    Spacer(minLength: 32)
                }
            }

            PrimaryButton(
                title: vm.isLastStep ? "Silence the alarm" : "Next verse",
                icon:  vm.isLastStep ? "bell.slash.fill" : "chevron.right"
            ) {
                vm.continueAfterReveal()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .task {
            if !parallelLanguage.isEmpty {
                parallelText = await EthiopianBibleService.shared.verse(ref: question.verseRef, language: parallelLanguage)
            }
        }
    }

    // MARK: - Verse card

    private var verseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Reference
            Text(question.verseRef.uppercased())
                .font(.system(size: 10, weight: .bold)).tracking(2)
                .foregroundStyle(DesignSystem.pastoralGold)

            // English text
            Text("\u{201C}\(question.verseText)\u{201D}")
                .font(DesignSystem.serif(14, italic: true))
                .foregroundStyle(DesignSystem.slate600)
                .fixedSize(horizontal: false, vertical: true)

            // Parallel translation (shown only when a language is selected + loaded)
            if let info = langInfo {
                Divider()
                    .padding(.vertical, 4)

                HStack(spacing: 6) {
                    Text(info.flagEmoji)
                        .font(.system(size: 11))
                    Text(info.nativeName)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(DesignSystem.pastoralGold)
                }

                if let text = parallelText {
                    Text(text)
                        .font(.system(size: 15))
                        .foregroundStyle(DesignSystem.slate700)
                        .fixedSize(horizontal: false, vertical: true)
                        .environment(\.layoutDirection, .leftToRight)
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.75)
                        Text("በመጫን ላይ…")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignSystem.slate400)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.pastoralGold.opacity(0.10))
        .cornerRadius(12)
        .overlay(Rectangle().fill(DesignSystem.pastoralGold).frame(width: 2), alignment: .leading)
    }
}
