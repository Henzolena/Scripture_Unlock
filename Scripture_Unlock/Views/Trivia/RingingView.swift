import SwiftUI

/// The full-bleed alarm screen shown when AlarmKit fires.
/// Overrides everything — only dismissible via trivia.
struct RingingView: View {
    let alarm: Alarm
    @State private var showTrivia = false

    var body: some View {
        ZStack {
            DesignSystem.midnightGradient.ignoresSafeArea()

            RadialGradient(
                colors: [DesignSystem.pastoralGold.opacity(0.12), .clear],
                center: .bottomTrailing, startRadius: 0, endRadius: 400
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(size: 13, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.6))

                Text(Date().formatted(.dateTime.hour(.twoDigits(amPM: .wide)).minute(.twoDigits)))
                    .font(.system(size: 88, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.top, 8)

                Spacer().frame(height: 36)

                PulsingGoldSeal()

                Spacer().frame(height: 24)

                Text(alarm.label.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(2.5)
                    .foregroundStyle(DesignSystem.pastoralGold.opacity(0.85))

                Text("\u{201C}Awake, my soul! Awake, O harp and lyre!\nI will awake the dawn!\u{201D}")
                    .font(DesignSystem.serif(17, italic: true))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 14)

                Text("Psalm 57:8")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 8)

                Spacer()

                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(DesignSystem.pastoralGold)
                    HStack(spacing: 0) {
                        Text("Snooze locked. Answer ")
                            .foregroundStyle(.white.opacity(0.8))
                        Text("\(alarm.effectiveQuestionCount) verses")
                            .foregroundStyle(DesignSystem.pastoralGold)
                            .fontWeight(.bold)
                        Text(" to silence.")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .font(.system(size: 12.5))
                .padding(14)
                .background(.white.opacity(0.06))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(DesignSystem.pastoralGold.opacity(0.25), lineWidth: 0.5))
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                PrimaryButton(title: "Begin", icon: "chevron.right", style: .gold) {
                    showTrivia = true
                }
                .padding(.horizontal, 24)

                Text("Drag the seal up for emergency stop")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 10)
                    .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showTrivia) {
            TriviaContainerView(alarm: alarm)
        }
    }
}

// MARK: - PulsingGoldSeal

struct PulsingGoldSeal: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(DesignSystem.pastoralGold.opacity(0.2), lineWidth: 1)
                .frame(width: 140, height: 140)
                .scaleEffect(pulse ? 1.15 : 1)
                .opacity(pulse ? 0 : 1)
                .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: pulse)

            Circle()
                .stroke(DesignSystem.pastoralGold.opacity(0.1), lineWidth: 1)
                .frame(width: 110, height: 110)
                .scaleEffect(pulse ? 1.2 : 1)
                .opacity(pulse ? 0 : 1)
                .animation(.easeOut(duration: 1.8).delay(0.3).repeatForever(autoreverses: false), value: pulse)

            GoldSeal(size: 90)
        }
        .onAppear { pulse = true }
    }
}
