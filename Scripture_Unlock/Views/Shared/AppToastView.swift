import SwiftUI

// MARK: - Global overlay (add once to RootView)

struct AppToastView: View {
    @Environment(ToastService.self)      private var toast
    @Environment(AchievementService.self) private var achievements

    var body: some View {
        ZStack(alignment: .bottom) {
            // Achievement unlock — rendered above the regular toast
            if let badge = achievements.newlyEarned {
                AchievementUnlockBanner(achievement: badge)
                    .padding(.bottom, 108)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
                    .onTapGesture { achievements.clearNewlyEarned() }
            }

            // Regular toast
            if let t = toast.current {
                ToastBanner(toast: t)
                    .padding(.bottom, 104)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: toast.current)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: achievements.newlyEarned?.id)
        .allowsHitTesting(achievements.newlyEarned != nil)
    }
}

// MARK: - Regular toast pill

private struct ToastBanner: View {
    let toast: ToastService.Toast

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: toast.icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(iconColor)
            Text(toast.message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignSystem.ink)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(DesignSystem.surface)
        .cornerRadius(24)
        .shadow(color: DesignSystem.shadow1, radius: 14, x: 0, y: 4)
    }

    private var iconColor: Color {
        switch toast.style {
        case .success: return DesignSystem.bethanyGreen
        case .gold:    return DesignSystem.pastoralGold
        case .warning: return DesignSystem.warning
        case .info:    return DesignSystem.royalBlue
        }
    }
}

// MARK: - Achievement unlock banner

struct AchievementUnlockBanner: View {
    let achievement: Achievement

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(DesignSystem.pastoralGold.opacity(0.20))
                    .frame(width: 46, height: 46)
                Image(systemName: achievement.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(DesignSystem.pastoralGold)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Achievement Unlocked")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(DesignSystem.pastoralGold)
                Text(achievement.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DesignSystem.ink)
                Text(achievement.description)
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.slate600)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DesignSystem.slate400)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            ZStack {
                DesignSystem.surface
                LinearGradient(
                    colors: [DesignSystem.pastoralGold.opacity(0.08), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
            }
        )
        .cornerRadius(18)
        .shadow(color: DesignSystem.pastoralGold.opacity(0.22), radius: 18, x: 0, y: 6)
        .shadow(color: DesignSystem.shadow1, radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
    }
}
