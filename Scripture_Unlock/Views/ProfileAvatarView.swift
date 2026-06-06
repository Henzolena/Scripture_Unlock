import SwiftUI

enum ProfileAvatarFallback {
    case initials
    case cross
}

struct ProfileAvatarView: View {
    let name: String
    let avatarPath: String
    var size: CGFloat = 52
    var fallback: ProfileAvatarFallback = .initials
    var showsGlow = true

    private var avatarURL: URL? {
        SupabaseService.shared.profileAvatarPublicURL(path: avatarPath)
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }

        let short = String(name.prefix(2)).uppercased()
        return short.isEmpty ? "?" : short
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(DesignSystem.goldGradient)

            if let avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        ProgressView()
                            .tint(Color(hex: "1E3A5F"))
                            .scaleEffect(0.8)
                    default:
                        fallbackContent
                    }
                }
            } else {
                fallbackContent
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(DesignSystem.pastoralGold.opacity(0.9), lineWidth: max(1.5, size * 0.035))
        )
        .shadow(
            color: showsGlow ? DesignSystem.pastoralGold.opacity(0.42) : .clear,
            radius: showsGlow ? max(8, size * 0.18) : 0,
            x: 0,
            y: 2
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var fallbackContent: some View {
        switch fallback {
        case .initials:
            Text(initials)
                .font(.system(size: max(14, size * 0.36), weight: .bold))
                .foregroundStyle(Color(hex: "1E3A5F"))
        case .cross:
            Image(systemName: "cross.fill")
                .font(.system(size: max(18, size * 0.43), weight: .bold))
                .foregroundStyle(Color(hex: "1E3A5F"))
        }
    }
}
