import SwiftUI

struct FillView: View {
    let question: TriviaQuestion
    @Bindable var vm: TriviaViewModel

    /// Translated fill structure when a parallel language is active.
    private var translated: TriviaViewModel.TranslatedFill? {
        vm.translatedFills[question.id]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Book / step badge ───────────────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "book.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.pastoralGold)
                Text("\(question.book) · \(vm.currentStep + 1) of \(vm.totalSteps)")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2).textCase(.uppercase)
                    .foregroundStyle(DesignSystem.pastoralGold)

                if question.isAIGenerated {
                    Text("✦ AI")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(DesignSystem.pastoralGold.opacity(0.7))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(DesignSystem.pastoralGold.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)

            // ── Language pill (shown when translating) ──────────────────────
            if let info = EthiopianBibleService.info(for: vm.parallelLanguage) {
                HStack(spacing: 5) {
                    Text(info.flagEmoji).font(.system(size: 10))
                    Text(info.nativeName)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(DesignSystem.pastoralGold)
                    if translated == nil {
                        // Still loading translation
                        ProgressView()
                            .scaleEffect(0.6)
                            .tint(DesignSystem.pastoralGold)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(DesignSystem.pastoralGold.opacity(0.10))
                .clipShape(Capsule())
                .padding(.horizontal, 24)
                .padding(.top, 8)
            } else {
                Text("Complete the verse")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DesignSystem.slate600)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
            }

            // ── Verse text with blank ──────────────────────────────────────
            verseText
                .padding(.horizontal, 24)
                .padding(.top, 12)

            // ── Answer chips ───────────────────────────────────────────────
            chipGrid
                .padding(.horizontal, 24)
                .padding(.top, 28)

            Spacer(minLength: 24)

            // ── Confirm / clear ────────────────────────────────────────────
            VStack(spacing: 12) {
                Button {
                    vm.confirmFill()
                } label: {
                    Text("Confirm answer")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(vm.fillPickedIndex == nil ? DesignSystem.slate400 : DesignSystem.deepBlue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(vm.fillPickedIndex == nil ? Color.primary.opacity(0.06) : DesignSystem.pastoralGold)
                        .cornerRadius(14)
                        .shadow(color: vm.fillPickedIndex == nil ? .clear : DesignSystem.pastoralGold.opacity(0.30),
                                radius: 8, x: 0, y: 4)
                }
                .disabled(vm.fillPickedIndex == nil)

                HStack {
                    Button("Clear") { vm.fillPickedIndex = nil }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DesignSystem.slate600)
                    Spacer()
                    Text("ESV · \(VersePack.find(question.packId).name)")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.slate400)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Verse with blank

    private var verseText: some View {
        // Use translated fill when available, otherwise fall back to English
        let pre    = translated?.pre  ?? question.fillPre  ?? ""
        let post   = translated?.post ?? question.fillPost ?? ""
        let opts   = translated?.options ?? question.options
        let filled = vm.fillPickedIndex.map { opts[$0] }

        var preAttr = AttributedString(pre + " ")
        preAttr.swiftUI.font            = DesignSystem.serif(26, italic: true)
        preAttr.swiftUI.foregroundColor = DesignSystem.ink

        var blankAttr = AttributedString(filled ?? "          ")
        blankAttr.swiftUI.font            = .system(size: 22, weight: .bold)
        blankAttr.swiftUI.foregroundColor = filled == nil ? DesignSystem.slate400 : DesignSystem.deepBlue

        var postAttr = AttributedString(" " + post)
        postAttr.swiftUI.font            = DesignSystem.serif(26, italic: true)
        postAttr.swiftUI.foregroundColor = DesignSystem.ink

        return Text(preAttr + blankAttr + postAttr)
    }

    // MARK: - Chip grid

    private var chipGrid: some View {
        // Use translated options when available
        let opts = translated?.options ?? question.options
        let cols = [GridItem(.flexible()), GridItem(.flexible())]

        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(Array(opts.enumerated()), id: \.offset) { index, word in
                let selected = vm.fillPickedIndex == index
                Button {
                    vm.pickFillOption(index: index)
                } label: {
                    Text(word)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(selected ? DesignSystem.slate400 : DesignSystem.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(selected ? Color.clear : DesignSystem.surface)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(selected ? Color.primary.opacity(0.18) : Color.clear,
                                        style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )
                        .shadow(color: selected ? .clear : DesignSystem.shadow1, radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
