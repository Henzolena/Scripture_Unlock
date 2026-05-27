import Foundation
import SwiftData

/// A user-created alarm stored locally via SwiftData.
@Model
final class Alarm {

    var id: UUID = UUID()
    var label: String = "Morning devotions"
    var hour: Int = 6
    var minute: Int = 0
    var isAM: Bool = true
    var isEnabled: Bool = true

    /// 0 = Sun, 1 = Mon … 6 = Sat. Empty = once.
    var repeatDays: [Int] = [1, 2, 3, 4, 5]

    var packId: String = VersePack.psalms.id
    var translationRaw: String = Translation.esv.rawValue
    var difficultyRaw: String = Difficulty.regular.rawValue
    var questionCount: Int = 3
    var snoozeCountToday: Int = 0
    var toneIdentifier: String = "scripture_unlock_morning"
    var createdAt: Date = Date()

    // MARK: Computed

    var translation: Translation {
        get { Translation(rawValue: translationRaw) ?? .esv }
        set { translationRaw = newValue.rawValue }
    }

    var difficulty: Difficulty {
        get { Difficulty(rawValue: difficultyRaw) ?? .regular }
        set { difficultyRaw = newValue.rawValue }
    }

    /// Total questions including snooze tax.
    var effectiveQuestionCount: Int {
        questionCount + snoozeCountToday
    }

    /// Fire time as Date for today (used by AlarmKit scheduling).
    var nextFireDate: Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = isAM ? hour : hour + 12
        comps.minute = minute
        comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    init(label: String = "Morning devotions", hour: Int = 6, minute: Int = 0) {
        self.id = UUID()
        self.label = label
        self.hour = hour
        self.minute = minute
    }
}

// MARK: - Enums

enum Translation: String, CaseIterable, Codable {
    case esv  = "ESV"
    case niv  = "NIV"
    case kjv  = "KJV"
    case nlt  = "NLT"
}

enum Difficulty: String, CaseIterable, Codable {
    case gentle  = "Gentle"
    case regular = "Regular"
    case scholar = "Scholar"
}
