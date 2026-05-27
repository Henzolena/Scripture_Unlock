import SwiftUI
import SwiftData

/// Coordinator for the 5-screen first-run flow.
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
            case 4: LockItDownView                          { finish() }
            default: Color.clear
            }
        }
        .animation(.easeInOut(duration: 0.28), value: step)
        .preferredColorScheme(.light)
    }

    private func finish() {
        context.insert(profile)
        Task { await SupabaseService.shared.upsertProfile(profile) }
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
