import SwiftUI

struct AchievementsView: View {
    @Environment(AchievementService.self) private var achievementService

    private let categoryOrder: [Achievement.Category] = [
        .streak, .mastery, .dedication, .community, .pack
    ]

    private var grouped: [Achievement.Category: [Achievement]] {
        Dictionary(grouping: Achievement.all, by: \.category)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            earnedBanner
            ForEach(categoryOrder, id: \.rawValue) { cat in
                if let items = grouped[cat] {
                    categorySection(cat, items: items)
                }
            }
        }
    }

    private var earnedBanner: some View {
        let count = achievementService.earnedIds.count
        let total = Achievement.all.count
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(DesignSystem.pastoralGold.opacity(0.14))
                    .frame(width: 46, height: 46)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(DesignSystem.pastoralGold)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(count) of \(total) earned")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DesignSystem.ink)
                ProgressView(value: Double(count), total: Double(total))
                    .tint(DesignSystem.pastoralGold)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .cardStyle()
    }

    private func categorySection(_ category: Achievement.Category, items: [Achievement]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: category.label)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    achievementRow(item)
                    if index < items.count - 1 {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .background(DesignSystem.surface)
            .cornerRadius(16)
            .shadow(color: DesignSystem.shadow1, radius: 8, x: 0, y: 2)
        }
    }

    private func achievementRow(_ item: Achievement) -> some View {
        let earned = achievementService.earnedIds.contains(item.id)
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(earned
                        ? DesignSystem.pastoralGold.opacity(0.15)
                        : DesignSystem.slate400.opacity(0.10))
                    .frame(width: 44, height: 44)
                Image(systemName: item.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(earned ? DesignSystem.pastoralGold : DesignSystem.slate400)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(earned ? DesignSystem.ink : DesignSystem.slate600)
                Text(item.description)
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.slate600)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if earned {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DesignSystem.pastoralGold)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignSystem.slate400.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
