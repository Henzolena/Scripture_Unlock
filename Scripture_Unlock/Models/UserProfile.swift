import Foundation
import SwiftData

/// Stored per-user by Supabase; mirrored locally for offline access.
@Model
final class UserProfile {
    var id: UUID = UUID()
    var name: String = ""
    var denomination: String = ""
    var activePackId: String = VersePack.psalms.id
    var translationRaw: String = Translation.esv.rawValue
    var questionCount: Int = 3
    var difficultyRaw: String = Difficulty.regular.rawValue
    var snoozeTaxEnabled: Bool = true
    var sabbathModeEnabled: Bool = true
    /// Language code for the parallel translation shown alongside English.
    /// "am" = Amharic · "or" = Oromo · "ti" = Tigrigna · "" = off
    var parallelLanguage: String = ""
    var accountabilityPartnerEmail: String = ""
    var avatarPath: String = ""
    /// "system" | "light" | "dark"
    var appearanceRaw: String = "system"
    var createdAt: Date = Date()

    init() {}
}

/// One row per morning — tracks the session that day.
@Model
final class StreakEntry {
    var id: UUID = UUID()
    var date: Date = Calendar.current.startOfDay(for: Date())
    var questionsAnswered: Int = 0
    var questionsCorrect: Int = 0
    var snoozeCount: Int = 0
    /// Set only when every question was answered. This is what counts as a
    /// completed morning — the friends leaderboard keys off it.
    var dismissedAt: Date?
    /// Set when the alarm was silenced with questions still outstanding, so
    /// bailing out is visible instead of scoring the same as finishing.
    var abandonedAt: Date?

    var accuracy: Double {
        guard questionsAnswered > 0 else { return 0 }
        return Double(questionsCorrect) / Double(questionsAnswered)
    }

    init(date: Date = Date()) {
        self.date = Calendar.current.startOfDay(for: date)
    }
}
