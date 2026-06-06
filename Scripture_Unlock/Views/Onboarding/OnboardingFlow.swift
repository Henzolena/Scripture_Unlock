import SwiftUI
import SwiftData
import AuthenticationServices

/// Coordinator for the 6-screen first-run flow.
struct OnboardingFlow: View {
    @State private var step = 0
    @State private var profile = UserProfile()
    @State private var isExistingAccountSignIn = false
    @Environment(\.modelContext) private var context

    var body: some View {
        ZStack {
            switch step {
            case 0:
                WelcomeView {
                    isExistingAccountSignIn = false
                    step = 1
                } onSignIn: {
                    isExistingAccountSignIn = true
                    step = 5
                }
            case 1: NameTraditionView  (profile: profile)   { step = 2 }
            case 2: PackPickerOnboard  (profile: profile)   { step = 3 }
            case 3: FirstAlarmView     (profile: profile)   { step = 4 }
            case 4: LockItDownView                          { step = 5 }
            case 5:
                SignInPromptView(
                    mode: isExistingAccountSignIn ? .existingAccount : .backupProgress,
                    onSignedIn: { finish(pushLocalProfile: !isExistingAccountSignIn) },
                    onSkip: {
                        if isExistingAccountSignIn {
                            isExistingAccountSignIn = false
                            step = 1
                        } else {
                            finish(pushLocalProfile: false)
                        }
                    }
                )
            default: Color.clear
            }
        }
        .animation(.easeInOut(duration: 0.28), value: step)
    }

    private func finish(pushLocalProfile: Bool) {
        context.insert(profile)
        // Only push to cloud if the user chose to sign in during onboarding.
        // upsertProfile is also called from ProfileView when editing, so
        // skipping here for local-only users is safe.
        let supabase = SupabaseService.shared
        if supabase.isSignedIn {
            Task {
                if pushLocalProfile {
                    await supabase.upsertProfile(profile)
                } else {
                    await supabase.syncFromCloud(context: context)
                    try? await Task.sleep(for: .milliseconds(500))
                    await supabase.syncFromCloud(context: context)
                }
            }
        }
    }
}

// MARK: - Sign-in prompt (step 5)

struct SignInPromptView: View {
    enum Mode {
        case backupProgress
        case existingAccount
    }

    let mode: Mode
    let onSignedIn: () -> Void
    let onSkip: () -> Void

    @Environment(SupabaseService.self) private var supabase

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

                Text(mode == .existingAccount ? "Sign in to your account" : "Back up your progress")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(DesignSystem.ink)
                    .padding(.top, 24)

                Text(mode == .existingAccount
                     ? "Use Apple or a one-time email code to restore your saved Scripture Unlock progress."
                     : "Sign in with Apple or email to keep your streak and settings safe even if you lose your phone.")
                    .font(.system(size: 15))
                    .foregroundStyle(DesignSystem.slate600)
                    .padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)

                // Benefits list
                VStack(spacing: 14) {
                    benefitRow(icon: "flame.fill",          color: DesignSystem.pastoralGold, text: "Never lose your daily streak")
                    benefitRow(icon: "iphone.and.arrow.forward.outward", color: DesignSystem.royalBlue, text: "Sync across all your devices")
                    benefitRow(icon: "person.badge.shield.checkmark.fill", color: DesignSystem.bethanyGreen, text: "No password to create or remember")
                }
                .padding(.top, 28)

                Spacer(minLength: 40)

                // Native Sign in with Apple button
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task {
                        await SupabaseService.shared.handleSignInResult(result)
                        if supabase.isSignedIn {
                            onSignedIn()
                        }
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 54)
                .cornerRadius(14)
                .padding(.top, 12)

                EmailOTPAuthView(
                    title: "Sign in with email",
                    subtitle: "We will send a one-time code. New users are welcomed automatically after verification.",
                    showsContainer: true,
                    successActionTitle: "Continue",
                    onSuccess: onSignedIn
                )
                .padding(.top, 14)

                // Skip option
                Button {
                    onSkip()
                } label: {
                    Text(mode == .existingAccount ? "Set up a new profile instead" : "Continue without account")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DesignSystem.slate600)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .padding(.top, 6)
                .padding(.bottom, 48)

                Text(mode == .existingAccount ? "You can create a new local setup if this device is for someone else." : "You can sign in anytime from Settings.")
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
