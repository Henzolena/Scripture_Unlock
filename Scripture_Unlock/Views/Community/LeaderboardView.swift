import SwiftUI
import Auth

struct LeaderboardView: View {
    @Environment(SupabaseService.self) private var supabase
    @State private var entries: [LeaderboardEntry] = []
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !supabase.isSignedIn {
                    signedOutPrompt
                } else if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if entries.isEmpty {
                    emptyState
                } else {
                    leaderList
                }
            }
            .padding(20)
        }
        .background(DesignSystem.warmCream.ignoresSafeArea())
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AppToolbarIconButton(systemName: "arrow.clockwise") {
                    Task { await load() }
                }
            }
        }
        .task { await load() }
    }

    private var leaderList: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                entryRow(rank: index + 1, entry: entry)
                if index < entries.count - 1 {
                    Divider().padding(.leading, 74)
                }
            }
        }
        .background(DesignSystem.surface)
        .cornerRadius(16)
        .shadow(color: DesignSystem.shadow1, radius: 8, x: 0, y: 2)
    }

    private func entryRow(rank: Int, entry: LeaderboardEntry) -> some View {
        HStack(spacing: 12) {
            rankBadge(rank)

            AvatarCircle(name: entry.name, avatarPath: entry.avatarPath, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name.isEmpty ? "Friend" : entry.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DesignSystem.ink)
                    .lineLimit(1)
                Text("\(entry.totalSessions) sessions")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.slate600)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.totalCorrect)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(rank == 1 ? DesignSystem.pastoralGold : DesignSystem.deepBlue)
                Text("correct")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignSystem.slate600)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(rank == 1 ? DesignSystem.pastoralGold.opacity(0.05) : Color.clear)
    }

    private func rankBadge(_ rank: Int) -> some View {
        ZStack {
            Circle()
                .fill(rankColor(rank).opacity(0.13))
                .frame(width: 30, height: 30)
            Text("\(rank)")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(rankColor(rank))
        }
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return DesignSystem.pastoralGold
        case 2: return DesignSystem.slate600
        case 3: return Color(hex: "CD7F32")
        default: return DesignSystem.slate400
        }
    }

    private var signedOutPrompt: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 20))
                .foregroundStyle(DesignSystem.pastoralGold)
            VStack(alignment: .leading, spacing: 4) {
                Text("Sign in to see rankings")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.ink)
                Text("Compare your Scripture accuracy against friends.")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.slate600)
            }
        }
        .padding(16)
        .cardStyle()
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 20))
                .foregroundStyle(DesignSystem.slate400)
            VStack(alignment: .leading, spacing: 4) {
                Text("No leaderboard yet")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.ink)
                Text("Add friends and complete sessions together to see rankings here.")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.slate600)
            }
        }
        .padding(16)
        .cardStyle()
    }

    private func load() async {
        guard supabase.isSignedIn,
              let session = try? await supabase.currentSession() else { return }
        await MainActor.run { isLoading = true }
        let host = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_HOST") as? String ?? ""
        let anon = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
        guard let url = URL(string: "https://\(host)/rest/v1/rpc/get_friends_leaderboard"),
              let body = try? JSONSerialization.data(withJSONObject: [
                "requesting_user_id": session.user.id.uuidString
              ]) else {
            await MainActor.run { isLoading = false }
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"; req.httpBody = body
        req.setValue(anon, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let rows = try? JSONDecoder().decode([LeaderboardEntry].self, from: data) {
            await MainActor.run { entries = rows }
        }
        await MainActor.run { isLoading = false }
    }
}

private struct LeaderboardEntry: Decodable, Identifiable {
    var id: String { userId }
    let userId: String
    let name: String
    let avatarPath: String
    let friendCode: String
    let totalCorrect: Int
    let totalSessions: Int

    enum CodingKeys: String, CodingKey {
        case name
        case userId       = "user_id"
        case avatarPath   = "avatar_path"
        case friendCode   = "friend_code"
        case totalCorrect = "total_correct"
        case totalSessions = "total_sessions"
    }
}
