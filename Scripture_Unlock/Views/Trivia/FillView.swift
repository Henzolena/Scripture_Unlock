import SwiftUI

struct FillView: View {
    let question: TriviaQuestion
    @Bindable var vm: TriviaViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "book.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.pastoralGold)
                Text("\(question.book) · \(vm.currentStep + 1) of \(vm.totalSteps)")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2).textCase(.uppercase)
                    .foregroundStyle(DesignSystem.pastoralGold)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)

            Text("Complete the verse")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DesignSystem.slate600)
                .padding(.horizontal, 24)
                .padding(.top, 10)

            verseText
                .padding(.horizontal, 24)
                .padding(.top, 12)

            chipGrid
                .padding(.horizontal, 24)
                .padding(.top, 28)

            Spacer(minLength: 24)

            VStack(spacing: 12) {
                Button {
                    vm.confirmFill()
                } label: {
                    Text("Confirm answer")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(vm.fillPickedIndex == nil ? DesignSystem.slate400 : DesignSystem.deepBlue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(vm.fillPickedIndex == nil ? Color.black.opacity(0.06) : DesignSystem.pastoralGold)
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
        let pre  = question.fillPre  ?? ""
        let post = question.fillPost ?? ""
        let filled = vm.fillPickedIndex.map { question.options[$0] }

        return Group {
            Text(pre + " ")
                .font(DesignSystem.serif(26, italic: true))
                .foregroundStyle(DesignSystem.ink)
            + Text(filled ?? "          ")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(filled == nil ? DesignSystem.slate400 : DesignSystem.deepBlue)
            + Text(" " + post)
                .font(DesignSystem.serif(26, italic: true))
                .foregroundStyle(DesignSystem.ink)
        }
    }

    // MARK: - Chip grid

    private var chipGrid: some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(Array(question.options.enumerated()), id: \.offset) { index, word in
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
                                .stroke(selected ? Color.black.opacity(0.18) : Color.clear,
                                        style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )
                        .shadow(color: selected ? .clear : DesignSystem.shadow1, radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
