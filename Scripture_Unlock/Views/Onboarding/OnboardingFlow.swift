import SwiftUI
import SwiftData
import AuthenticationServices

/// Coordinator for the 6-screen first-run flow.
struct OnboardingFlow: View {
    @State private var step = 0
    @State private var profile = UserProfile()
    @Environment(\.modelContext) private var context

    var body: some View {
        ZStack {
            switch step {
            case 0: WelcomeView        { step = 1 }
            case 1: NameTraditionView  (profile: profile)   { step = 2 }
            case 2: PackPickerOnboard  (profile: profile)   { step = 3 }
            case 3: FirstAlarmView     (profile: profile)   { step = 4 }
            case 4: LockItDownView                          { step = 5 }
            case 5: SignInPromptView                        { finish() }
            default: Color.clear
            }
        }
        .animation(.easeInOut(duration: 0.28), value: step)
    }

    private func finish() {
        context.insert(profile)
        // Only push to cloud if the user chose to sign in during onboarding.
        // upsertProfile is also called from ProfileView when editing, so
        // skipping here for local-only users is safe.
        let supabase = SupabaseService.shared
        if supabase.isSignedIn {
            Task { await supabase.upsertProfile(profile) }
        }
    }
}

// MARK: - Sign-in prompt (step 5)

struct SignInPromptView: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Top icon
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(DesignSystem.goldGradient)
                            .frame(width: 72, height: 72)
                        Image(systemName: "icloud.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color(hex: "1E3A5F"))
                    }
                    Spacer()
                }
                .padding(.top, 60)

                Text("Back up your progress")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(DesignSystem.ink)
                    .padding(.top, 24)

                Text("Sign in with Apple to keep your streak and settings safe — even if you lose your phone.")
                    .font(.system(size: 15))
                    .foregroundStyle(DesignSystem.slate600)
                    .padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)

                // Benefits list
                VStack(spacing: 14) {
                    benefitRow(icon: "flame.fill",          color: DesignSystem.pastoralGold, text: "Never lose your daily streak")
                    benefitRow(icon: "iphone.and.arrow.forward.outward", color: DesignSystem.royalBlue, text: "Sync across all your devices")
                    benefitRow(icon: "person.badge.shield.checkmark.fill", color: DesignSystem.bethanyGreen, text: "Private — Apple never shares your email")
                }
                .padding(.top, 28)

                Spacer(minLength: 40)

                // Native Sign in with Apple button
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task {
                        await SupabaseService.shared.handleSignInResult(result)
                        onContinue()
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 54)
                .cornerRadius(14)
                .padding(.top, 12)

                // Skip option
                Button {
                    onContinue()
                } label: {
                    Text("Continue without account")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DesignSystem.slate600)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .padding(.top, 6)
                .padding(.bottom, 48)

                Text("You can sign in anytime from Settings.")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.slate400)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 32)
            }
            .padding(.horizontal, 28)
        }
        .background(DesignSystem.warmCream.ignoresSafeArea())
    }

    private func benefitRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
            }
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DesignSystem.ink)
            Spacer()
        }
        .padding(14)
        .background(DesignSystem.surface)
        .cornerRadius(14)
        .shadow(color: DesignSystem.shadow1, radius: 6, x: 0, y: 2)
    }
}

// MARK: - Progress dots shared component

struct OnboardingDots: View {
    let total: Int
    let current: Int   // 1-based

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...total, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? DesignSystem.pastoralGold : DesignSystem.slate400.opacity(0.35))
                    .frame(width: i == current ? 24 : 6, height: 6)
                    .animation(.spring(duration: 0.3), value: current)
            }
        }
    }
}
