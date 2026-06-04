import SwiftUI

struct MCQView: View {
    let question: TriviaQuestion
    @Bindable var vm: TriviaViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            bookBadge
                .padding(.horizontal, 24)
                .padding(.top, 28)

            Text(question.prompt ?? "")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(DesignSystem.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 14)

            VStack(spacing: 10) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    OptionButton(
                        letter: String(UnicodeScalar(65 + index)!),
                        text: option
                    ) {
                        vm.submitMCQ(pickedIndex: index)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            Spacer(minLength: 32)

            HStack {
                Spacer()
                Text("\(VersePack.find(question.packId).name)")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.slate400)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private var bookBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "book.fill")
                .font(.system(size: 12))
                .foregroundStyle(DesignSystem.pastoralGold)
            Text("\(question.book) · \(vm.currentStep + 1) of \(vm.totalSteps)\(vm.lastMissedQuestion != nil ? " · take 2" : "")")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(DesignSystem.pastoralGold)
        }
    }
}

// MARK: - Option button

struct OptionButton: View {
    let letter: String
    let text: String
    let action: () -> Void

    @State private var pressing = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 36, height: 36)
                    Text(letter)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DesignSystem.slate600)
                }

                Text(text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DesignSystem.ink)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding(.leading, 12)
            .padding(.trailing, 18)
            .frame(minHeight: 64)
            .background(DesignSystem.surface)
            .cornerRadius(16)
            .shadow(color: DesignSystem.shadow1, radius: 6, x: 0, y: 2)
            .scaleEffect(pressing ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.12), value: pressing)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in pressing = true }
            .onEnded   { _ in pressing = false }
        )
    }
}
