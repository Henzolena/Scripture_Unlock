import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void
    let onSignIn: () -> Void

    private let pillars = [
        ("lock.fill",            "No skipping",  "Three correct answers before the alarm stops."),
        ("arrow.counterclockwise","No guessing", "Miss a verse and a different one appears."),
        ("flame.fill",           "Daily growth", "A streak you keep with God, not the app."),
    ]

    var body: some View {
        ZStack {
            DesignSystem.midnightGradient.ignoresSafeArea()
            RadialGradient(colors: [DesignSystem.pastoralGold.opacity(0.14), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 450)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                OnboardingDots(total: 5, current: 1)

                Spacer().frame(height: 48)

                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(hex: "1E3A5F"), Color(hex: "2563EB")],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 130, height: 130)
                        .shadow(color: DesignSystem.pastoralGold.opacity(0.25), radius: 24)
                    GoldSeal(size: 70)
                }

                VStack(spacing: 4) {
                    HStack(alignment: .center, spacing: 10) {
                        Text("Scripture")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                        Image(systemName: "key.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(DesignSystem.pastoralGold)
                            .rotationEffect(.degrees(-35))
                        Text("Unlock")
                            .font(DesignSystem.serif(34, italic: true))
                            .foregroundStyle(DesignSystem.pastoralGold)
                    }
                    Text("Three verses to unlock the day")
                        .font(.system(size: 12, weight: .medium))
                        .tracking(2.5).textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.top, 28)

                Text("Each morning, answer three verses from Scripture before the alarm can be silenced.")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 20)

                Spacer()

                VStack(spacing: 16) {
                    ForEach(pillars, id: \.0) { icon, title, sub in
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(DesignSystem.pastoralGold.opacity(0.18))
                                    .frame(width: 40, height: 40)
                                Image(systemName: icon)
                                    .foregroundStyle(DesignSystem.pastoralGold)
                                    .font(.system(size: 18))
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                Text(sub).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                            }
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)

                PrimaryButton(title: "Begin", icon: "chevron.right", style: .gold, action: onContinue)
                    .padding(.horizontal, 24)

                AppActionButton(
                    title: "Sign in",
                    icon: "person.crop.circle.badge.checkmark",
                    style: .neutral,
                    size: .compact,
                    action: onSignIn
                )
                .padding(.horizontal, 24)
                .padding(.top, 10)
                    .padding(.bottom, 48)
            }
        }
        .preferredColorScheme(.dark)
    }
}
