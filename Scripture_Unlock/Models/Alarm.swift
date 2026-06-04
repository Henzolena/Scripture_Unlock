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
    var toneIdentifier: String = "alarm_digital_pure"
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

    /// Returns the actual next Date this alarm will fire, accounting for repeat days.
    /// Returns nil if the alarm is disabled or has no future occurrence in the next 7 days.
    var nextActualFireDate: Date? {
        guard isEnabled else { return nil }
        let cal   = Calendar.current
        let now   = Date()
        let h24   = isAM ? hour : hour + 12

        if repeatDays.isEmpty {
            // One-time: use today if time hasn't passed, else tomorrow
            var c = cal.dateComponents([.year, .month, .day], from: now)
            c.hour = h24; c.minute = minute; c.second = 0
            if let d = cal.date(from: c), d > now { return d }
            if let tomorrow = cal.date(byAdding: .day, value: 1, to: now) {
                var c2 = cal.dateComponents([.year, .month, .day], from: tomorrow)
                c2.hour = h24; c2.minute = minute; c2.second = 0
                return cal.date(from: c2)
            }
            return nil
        }

        // Repeating: scan next 7 days for the soonest day in repeatDays
        // repeatDays uses 0=Sun…6=Sat; Calendar.weekday is 1=Sun…7=Sat
        for offset in 0..<7 {
            let candidate = cal.date(byAdding: .day, value: offset, to: now)!
            let weekday   = cal.component(.weekday, from: candidate) - 1  // 0…6
            guard repeatDays.contains(weekday) else { continue }
            var c = cal.dateComponents([.year, .month, .day], from: candidate)
            c.hour = h24; c.minute = minute; c.second = 0
            if let d = cal.date(from: c), d > now { return d }
        }
        return nil
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

    /// Maps to the Railway API's difficulty strings.
    var railwayValue: String {
        switch self {
        case .gentle:  return "beginner"
        case .regular: return "intermediate"
        case .scholar: return "advanced"
        }
    }
}
