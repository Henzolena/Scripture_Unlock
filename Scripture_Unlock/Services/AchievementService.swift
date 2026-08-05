import Foundation
import Auth

// MARK: - Model

struct Achievement: Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let category: Category

    enum Category: String {
        case streak, mastery, community, dedication, pack
        var label: String {
            switch self {
            case .streak:      return "Streak"
            case .mastery:     return "Mastery"
            case .community:   return "Community"
            case .dedication:  return "Dedication"
            case .pack:        return "Pack"
            }
        }
    }

    static let all: [Achievement] = [
        .init(id: "first_alarm",     title: "First Alarm",        description: "Completed your very first morning session",            icon: "alarm.fill",             category: .dedication),
        .init(id: "streak_3",        title: "3-Day Streak",       description: "Answered Scripture three days in a row",              icon: "flame.fill",             category: .streak),
        .init(id: "streak_7",        title: "Week of the Word",   description: "Kept the Word alive for 7 straight days",             icon: "flame.fill",             category: .streak),
        .init(id: "streak_14",       title: "Fortnight Faithful", description: "Two weeks without missing a morning session",         icon: "sparkles",               category: .streak),
        .init(id: "streak_30",       title: "Month of Devotion",  description: "Thirty consecutive days in the Word",                 icon: "crown.fill",             category: .streak),
        .init(id: "streak_90",       title: "Quarter Champion",   description: "90 days of unbroken morning devotion",                icon: "medal.fill",             category: .streak),
        .init(id: "streak_365",      title: "Year of the Word",   description: "A full year of daily Scripture devotion",             icon: "trophy.fill",            category: .streak),
        .init(id: "verses_50",       title: "50 Verses",          description: "Answered 50 Scripture questions correctly",           icon: "book.fill",              category: .mastery),
        .init(id: "verses_200",      title: "200 Verses",         description: "Mastered 200 Scripture answers",                      icon: "books.vertical.fill",    category: .mastery),
        .init(id: "verses_500",      title: "500 Verses",         description: "Half a thousand correct answers",                     icon: "text.book.closed.fill",  category: .mastery),
        .init(id: "pack_complete",   title: "Pack Graduate",      description: "Mastered every verse in a single pack",               icon: "graduationcap.fill",     category: .pack),
        .init(id: "first_friend",    title: "First Friend",       description: "Connected with your first friend",                    icon: "person.2.fill",          category: .community),
        .init(id: "first_room",      title: "Study Host",         description: "Created your first community study room",             icon: "house.fill",             category: .community),
        .init(id: "early_bird",      title: "Early Bird",         description: "Completed a session before 6 AM",                    icon: "sunrise.fill",           category: .dedication),
        .init(id: "perfect_session", title: "Perfect Session",    description: "Answered every question correctly in one session",    icon: "checkmark.seal.fill",    category: .dedication),
        .init(id: "bookmark_10",     title: "Avid Reader",        description: "Bookmarked 10 or more verses",                       icon: "bookmark.fill",          category: .mastery),
    ]

    static func find(_ id: String) -> Achievement? { all.first { $0.id == id } }
}

// MARK: - Context passed in from views that have SwiftData access

struct AchievementContext {
    var streak: Int = 0
    var totalCorrect: Int = 0
    var bookmarkCount: Int = 0
    var isFirstAlarm: Bool = false
    var isPerfectSession: Bool = false
    var sessionHour: Int? = nil          // 0–23, used for early bird
    var friendCount: Int = 0
    var hasCreatedRoom: Bool = false
    var completedAnyPack: Bool = false
}

// MARK: - Service

@Observable
final class AchievementService {
    static let shared = AchievementService()
    private init() {}

    private(set) var earnedIds: Set<String> = []
    /// Set after awarding — cleared by views after showing the unlock toast.
    private(set) var newlyEarned: Achievement? = nil

    var earned: [Achievement] { Achievement.all.filter { earnedIds.contains($0.id) } }
    var unearned: [Achievement] { Achievement.all.filter { !earnedIds.contains($0.id) } }

    func load() async {
        guard SupabaseService.shared.isSignedIn,
              let session = try? await SupabaseService.shared.currentSession() else { return }
        let rows: [EarnedRow]? = await sbGet(
            path: "user_achievements",
            query: "user_id=eq.\(session.user.id.uuidString)&select=achievement_id",
            token: session.accessToken
        )
        await MainActor.run {
            earnedIds = Set(rows?.map(\.achievementId) ?? [])
        }
    }

    func check(_ ctx: AchievementContext) async {
        guard SupabaseService.shared.isSignedIn else { return }

        var candidates: [String] = []

        if ctx.isFirstAlarm                       { candidates.append("first_alarm") }
        if ctx.isPerfectSession                   { candidates.append("perfect_session") }
        if let h = ctx.sessionHour, h < 6        { candidates.append("early_bird") }
        if ctx.completedAnyPack                   { candidates.append("pack_complete") }
        if ctx.friendCount >= 1                   { candidates.append("first_friend") }
        if ctx.hasCreatedRoom                     { candidates.append("first_room") }
        if ctx.bookmarkCount >= 10                { candidates.append("bookmark_10") }

        for (threshold, id): (Int, String) in [
            (3, "streak_3"), (7, "streak_7"), (14, "streak_14"),
            (30, "streak_30"), (90, "streak_90"), (365, "streak_365")
        ] { if ctx.streak >= threshold { candidates.append(id) } }

        for (threshold, id): (Int, String) in [
            (50, "verses_50"), (200, "verses_200"), (500, "verses_500")
        ] { if ctx.totalCorrect >= threshold { candidates.append(id) } }

        for id in candidates where !earnedIds.contains(id) {
            await award(id: id)
        }
    }

    func clearNewlyEarned() {
        Task { @MainActor in newlyEarned = nil }
    }

    // MARK: - Private

    private func award(id: String) async {
        guard !earnedIds.contains(id),
              let session = try? await SupabaseService.shared.currentSession() else { return }
        await sbPost(
            path: "user_achievements",
            body: ["user_id": session.user.id.uuidString, "achievement_id": id],
            token: session.accessToken
        )
        await MainActor.run {
            earnedIds.insert(id)
            newlyEarned = Achievement.find(id)
            ToastService.shared.fire(.success)
            // Second impact for a "double-tap" feel on achievement unlock
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                ToastService.shared.fire(.medium)
            }
        }
    }

    private var sbURL: String { Bundle.main.object(forInfoDictionaryKey: "SUPABASE_HOST") as? String ?? "" }
    private var sbAnon: String { Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? "" }

    private struct EarnedRow: Decodable {
        let achievementId: String
        enum CodingKeys: String, CodingKey { case achievementId = "achievement_id" }
    }

    private func sbGet<T: Decodable>(path: String, query: String, token: String) async -> T? {
        guard let url = URL(string: "https://\(sbURL)/rest/v1/\(path)?\(query)") else { return nil }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        req.setValue(sbAnon, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func sbPost(path: String, body: [String: Any], token: String) async {
        guard let url = URL(string: "https://\(sbURL)/rest/v1/\(path)"),
              let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"; req.httpBody = httpBody
        req.setValue(sbAnon, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("resolution=ignore-duplicates", forHTTPHeaderField: "Prefer")
        _ = try? await URLSession.shared.data(for: req)
    }
}
