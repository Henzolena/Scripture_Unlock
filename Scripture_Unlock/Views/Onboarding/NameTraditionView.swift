import SwiftUI

struct NameTraditionView: View {
    let profile: UserProfile
    let onContinue: () -> Void

    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OnboardingDots(total: 5, current: 2)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)

                Text("About you")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2.5)
                    .textCase(.uppercase)
                    .foregroundStyle(DesignSystem.slate600)
                    .padding(.top, 36)

                Text("What should we\ncall you?")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(DesignSystem.ink)
                    .padding(.top, 10)

                Text("Your name appears on the morning greeting and your streak.")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignSystem.slate600)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(DesignSystem.slate600)

                    TextField("Your name", text: $name)
                        .font(.system(size: 18, weight: .medium))
                        .focused($focused)
                        .padding(.horizontal, 18)
                        .frame(height: 56)
                        .background(DesignSystem.surface)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    focused ? DesignSystem.royalBlue : Color.black.opacity(0.1),
                                    lineWidth: focused ? 1.5 : 0.5
                                )
                        )
                        .shadow(color: DesignSystem.shadow1, radius: 6, x: 0, y: 2)
                }
                .padding(.top, 28)

                Spacer(minLength: 48)

                PrimaryButton(title: "Continue", icon: "chevron.right") {
                    profile.name = name.trimmingCharacters(in: .whitespaces)
                    onContinue()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.bottom, 48)
            }
            .padding(.horizontal, 24)
        }
        .background(DesignSystem.warmCream.ignoresSafeArea())
        .onAppear { focused = true }
    }
}
