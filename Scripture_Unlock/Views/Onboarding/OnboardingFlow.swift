import SwiftUI
import SwiftData
import AuthenticationServices

// MARK: - Flow coordinator

struct OnboardingFlow: View {
    @State private var defaultProfile = UserProfile()
    @State private var isSyncing = false
    @Environment(\.modelContext) private var context
    @Environment(SupabaseService.self) private var supabase

    var body: some View {
        if isSyncing {
            SyncingView()
        } else {
            WelcomeAuthView(
                onSignedIn: { Task { await finishWithAccount() } },
                onGuest:    { finishAsGuest() }
            )
        }
    }

    // MARK: - Private helpers

    /// Signed-in path: pull any existing cloud profile first; only create a new
    /// local profile if the user is genuinely new (nothing came down from cloud).
    @MainActor
    private func finishWithAccount() async {
        isSyncing = true
        await SupabaseService.shared.syncFromCloud(context: context)
        try? await Task.sleep(for: .milliseconds(400))
        let existing = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        if existing.isEmpty {
            context.insert(defaultProfile)
            await SupabaseService.shared.upsertProfile(defaultProfile)
        }
        // Once a profile exists, RootView's @Query picks it up and shows MainTabView.
        isSyncing = false
    }

    /// Guest path: create a local-only profile with defaults.
    private func finishAsGuest() {
        context.insert(defaultProfile)
    }
}

// MARK: - Single welcome + auth screen

struct WelcomeAuthView: View {
    let onSignedIn: () -> Void
    let onGuest:    () -> Void

    @Environment(SupabaseService.self) private var supabase

    private let features: [(String, String)] = [
        ("lock.fill",               "Alarm won't stop until you answer three Bible verses"),
        ("flame.fill",              "Build a daily streak rooted in actual Scripture"),
        ("arrow.counterclockwise",  "Wrong answers swap out — no guessing through"),
    ]

    var body: some View {
        ZStack {
            DesignSystem.midnightGradient.ignoresSafeArea()
            RadialGradient(
                colors: [DesignSystem.pastoralGold.opacity(0.12), .clear],
                center: .bottomTrailing, startRadius: 0, endRadius: 460
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Branding
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(hex: "1E3A5F"), Color(hex: "2563EB")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 100, height: 100)
                        .shadow(color: DesignSystem.pastoralGold.opacity(0.25), radius: 20)
                    GoldSeal(size: 54)
                }

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
                .padding(.top, 20)

                Text("Three verses to unlock the day")
                    .font(.system(size: 12, weight: .medium))
                    .tracking(2.5)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 4)

                // Feature rows
                VStack(spacing: 10) {
                    ForEach(features, id: \.0) { icon, text in
                        featureRow(icon: icon, text: text)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 36)

                Spacer()

                // Auth section
                VStack(spacing: 14) {

                    // Sign in with Apple
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        Task {
                            await SupabaseService.shared.handleSignInResult(result)
                            if supabase.isSignedIn { onSignedIn() }
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 54)
                    .cornerRadius(14)

                    // Divider
                    HStack {
                        Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
                        Text("or")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.3))
                            .padding(.horizontal, 10)
                        Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
                    }

                    // Guest button
                    Button(action: onGuest) {
                        Text("Continue without signing in")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(.white.opacity(0.07))
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(.white.opacity(0.12), lineWidth: 1)
                            )
                    }

                    // Trade-off note
                    HStack(spacing: 0) {
                        tradeOff("Streak lost if app is deleted")
                        Spacer()
                        Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 12)
                        Spacer()
                        tradeOff("No sync across devices")
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 52)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignSystem.pastoralGold)
                .frame(width: 18, alignment: .center)
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
        }
    }

    private func tradeOff(_ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(DesignSystem.pastoralGold.opacity(0.6))
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

// MARK: - Syncing overlay (shown while pulling existing cloud profile)

private struct SyncingView: View {
    var body: some View {
        ZStack {
            DesignSystem.midnightGradient.ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .tint(DesignSystem.pastoralGold)
                    .scaleEffect(1.2)
                Text("Loading your profile…")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Sign-in prompt (re-used from Settings → Account)

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
                     ? "Use Apple to restore your saved Scripture Unlock progress."
                     : "Sign in with Apple to keep your streak safe even if you lose your phone.")
                    .font(.system(size: 15))
                    .foregroundStyle(DesignSystem.slate600)
                    .padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 14) {
                    benefitRow(icon: "flame.fill",          color: DesignSystem.pastoralGold, text: "Never lose your daily streak")
                    benefitRow(icon: "iphone.and.arrow.forward.outward", color: DesignSystem.royalBlue, text: "Sync across all your devices")
                    benefitRow(icon: "person.badge.shield.checkmark.fill", color: DesignSystem.bethanyGreen, text: "No password to create or remember")
                }
                .padding(.top, 28)

                Spacer(minLength: 40)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task {
                        await SupabaseService.shared.handleSignInResult(result)
                        if supabase.isSignedIn { onSignedIn() }
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 54)
                .cornerRadius(14)
                .padding(.top, 12)

                EmailOTPAuthView(
                    title: "Sign in with email",
                    subtitle: "We'll send a one-time code. New users are welcomed automatically.",
                    showsContainer: true,
                    successActionTitle: "Continue",
                    onSuccess: onSignedIn
                )
                .padding(.top, 14)

                Button { onSkip() } label: {
                    Text(mode == .existingAccount ? "Set up a new profile instead" : "Continue without account")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DesignSystem.slate600)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .padding(.top, 6)
                .padding(.bottom, 48)

                Text(mode == .existingAccount
                     ? "You can create a new local setup if this device is for someone else."
                     : "You can sign in anytime from Settings.")
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

// MARK: - Progress dots (shared UI component)

struct OnboardingDots: View {
    let total: Int
    let current: Int

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
