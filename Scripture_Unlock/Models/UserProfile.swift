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
    var amharicAlongside: Bool = false
    var accountabilityPartnerEmail: String = ""
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
    var dismissedAt: Date?

    var accuracy: Double {
        guard questionsAnswered > 0 else { return 0 }
        return Double(questionsCorrect) / Double(questionsAnswered)
    }

    init(date: Date = Date()) {
        self.date = Calendar.current.startOfDay(for: date)
    }
}
