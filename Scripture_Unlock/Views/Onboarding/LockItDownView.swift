import SwiftUI

/// Screen Time + accountability partner setup — final onboarding step.
/// Also accessible from Settings.
struct LockItDownView: View {
    var onContinue: (() -> Void)? = nil
    @State private var partnerEmail = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if onContinue != nil {
                    OnboardingDots(total: 5, current: 5).frame(maxWidth: .infinity).padding(.top, 16)
                }

                Text("Make it stick")
                    .font(.system(size: 11, weight: .bold)).tracking(2.5).textCase(.uppercase)
                    .foregroundStyle(DesignSystem.slate600).padding(.top, 36)

                Text("Lock the app\nto your phone.")
                    .font(.system(size: 28, weight: .bold)).foregroundStyle(DesignSystem.ink).padding(.top, 10)

                Text("So your sleepy self can't delete the app to escape the morning verses.")
                    .font(.system(size: 14)).foregroundStyle(DesignSystem.slate600).padding(.top, 6)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12).fill(DesignSystem.royalBlue.opacity(0.18)).frame(width: 40, height: 40)
                            Image(systemName: "shield.fill").foregroundStyle(DesignSystem.royalBlue)
                        }
                        VStack(alignment: .leading) {
                            Text("Step 1 of 2").font(.system(size: 10, weight: .bold)).tracking(2).textCase(.uppercase).foregroundStyle(DesignSystem.pastoralGold)
                            Text("Block uninstall via Screen Time").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        }
                        Spacer()
                    }
                    Text("We'll open Settings so you can add Scripture Unlock to \"Apps that can't be deleted\". Takes 30 seconds.")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.78)).fixedSize(horizontal: false, vertical: true)

                    Button {
                        openScreenTimeSettings()
                    } label: {
                        HStack {
                            Text("Open Settings")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DesignSystem.deepBlue)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                }
                .padding(18)
                .background(DesignSystem.deepBlueGradient)
                .cornerRadius(18)
                .shadow(color: DesignSystem.deepBlue.opacity(0.22), radius: 12, x: 0, y: 6)
                .padding(.top, 22)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12).fill(DesignSystem.pastoralGold.opacity(0.18)).frame(width: 40, height: 40)
                            Image(systemName: "hands.and.sparkles.fill").foregroundStyle(Color(hex: "9C7E3B"))
                        }
                        VStack(alignment: .leading) {
                            Text("Step 2 of 2").font(.system(size: 10, weight: .bold)).tracking(2).textCase(.uppercase).foregroundStyle(DesignSystem.pastoralGold)
                            Text("Add an accountability partner").font(.system(size: 16, weight: .bold)).foregroundStyle(DesignSystem.ink)
                        }
                        Spacer()
                    }
                    Text("They can see your streak. They hold the unlock code — a spouse, a small-group leader, or your pastor.")
                        .font(.system(size: 13)).foregroundStyle(DesignSystem.slate600).fixedSize(horizontal: false, vertical: true)

                    TextField("partner@church.org", text: $partnerEmail)
                        .keyboardType(.emailAddress).autocorrectionDisabled()
                        .padding(.horizontal, 16).frame(height: 48)
                        .background(DesignSystem.warmCream)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.1), lineWidth: 0.5))
                }
                .padding(18)
                .background(DesignSystem.surface)
                .cornerRadius(18)
                .shadow(color: DesignSystem.shadow1, radius: 8, x: 0, y: 2)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06), lineWidth: 0.5))
                .padding(.top, 12)

                Spacer(minLength: 40)

                if let onContinue {
                    PrimaryButton(title: "Start setup", icon: "shield.fill", action: onContinue)
                    Button("I'll do this later") { onContinue() }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DesignSystem.slate600)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                        .padding(.bottom, 48)
                } else {
                    PrimaryButton(title: "Save") { dismiss() }.padding(.bottom, 48)
                }
            }
            .padding(.horizontal, 24)
        }
        .background(DesignSystem.warmCream.ignoresSafeArea())
        .navigationTitle(onContinue == nil ? "Lock it down" : "")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openScreenTimeSettings() {
        if let url = URL(string: "App-prefs:SCREEN_TIME") {
            UIApplication.shared.open(url)
        }
    }
}
