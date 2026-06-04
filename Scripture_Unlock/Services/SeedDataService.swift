import Foundation
import SwiftData

/// Populates realistic-looking sample data so the UI can be reviewed
/// with a real streak history, alarms, and profile settings.
/// Only runs when no StreakEntry records exist yet.
enum SeedDataService {

    static func seedIfNeeded(context: ModelContext) {
        let existingStreaks = (try? context.fetch(FetchDescriptor<StreakEntry>())) ?? []
        guard existingStreaks.isEmpty else { return }

        seedStreaks(context: context)
        seedAlarms(context: context)
        updateProfile(context: context)
    }

    // MARK: - Streak history (last 47 days — a solid 3-week current streak)

    private static func seedStreaks(context: ModelContext) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Map of daysAgo → (answered, correct, snoozes, dismissed)
        // nil dismissed = day not completed
        let data: [(daysAgo: Int, answered: Int, correct: Int, snoozes: Int, completed: Bool)] = [
            // Current streak — 21 days straight
            (0,  3, 3, 0, true),
            (1,  3, 2, 0, true),
            (2,  4, 4, 1, true),   // snooze tax kicked in
            (3,  3, 3, 0, true),
            (4,  3, 2, 0, true),
            (5,  1, 1, 0, true),   // Sunday sabbath mode (1 question)
            (6,  3, 3, 0, true),
            (7,  3, 3, 0, true),
            (8,  4, 3, 1, true),
            (9,  3, 3, 0, true),
            (10, 3, 2, 0, true),
            (11, 3, 3, 0, true),
            (12, 1, 1, 0, true),   // Sunday
            (13, 3, 3, 0, true),
            (14, 3, 2, 0, true),
            (15, 5, 4, 2, true),   // two snoozes
            (16, 3, 3, 0, true),
            (17, 3, 3, 0, true),
            (18, 3, 2, 0, true),
            (19, 1, 1, 0, true),   // Sunday
            (20, 3, 3, 0, true),
            // Streak break — missed 3 days
            (21, 0, 0, 0, false),
            (22, 0, 0, 0, false),
            (23, 0, 0, 0, false),
            // Previous streak — 11 days
            (24, 3, 2, 0, true),
            (25, 3, 3, 0, true),
            (26, 1, 1, 0, true),   // Sunday
            (27, 3, 3, 0, true),
            (28, 3, 3, 0, true),
            (29, 4, 3, 1, true),
            (30, 3, 2, 0, true),
            (31, 3, 3, 0, true),
            (32, 3, 3, 0, true),
            (33, 1, 1, 0, true),   // Sunday
            (34, 3, 3, 0, true),
            // Small gap
            (35, 0, 0, 0, false),
            // Earlier activity
            (36, 3, 2, 0, true),
            (37, 3, 3, 0, true),
            (38, 3, 3, 0, true),
            (39, 1, 1, 0, true),   // Sunday
            (40, 3, 2, 0, true),
            (41, 3, 3, 0, true),
            (42, 3, 3, 0, true),
            (43, 0, 0, 0, false),
            (44, 3, 3, 0, true),
            (45, 3, 2, 0, true),
            (46, 3, 3, 0, true),
        ]

        for record in data {
            guard record.completed else { continue }
            let entry = StreakEntry(date: cal.date(byAdding: .day, value: -record.daysAgo, to: today)!)
            entry.questionsAnswered = record.answered
            entry.questionsCorrect  = record.correct
            entry.snoozeCount       = record.snoozes
            entry.dismissedAt       = cal.date(byAdding: .hour, value: 7, to: entry.date)
            context.insert(entry)
        }
    }

    // MARK: - Alarms

    private static func seedAlarms(context: ModelContext) {
        let alarms: [(label: String, hour: Int, minute: Int, isAM: Bool,
                      days: [Int], pack: String, count: Int, difficulty: String)] = [
            (
                label:      "Morning Prayer",
                hour:       6,
                minute:     0,
                isAM:       true,
                days:       [1, 2, 3, 4, 5],       // Mon–Fri
                pack:       VersePack.psalms.id,
                count:      3,
                difficulty: Difficulty.regular.rawValue
            ),
            (
                label:      "Weekend Devotion",
                hour:       8,
                minute:     30,
                isAM:       true,
                days:       [0, 6],                 // Sat–Sun
                pack:       VersePack.gospels.id,
                count:      3,
                difficulty: Difficulty.gentle.rawValue
            ),
            (
                label:      "Deep Study",
                hour:       5,
                minute:     45,
                isAM:       true,
                days:       [1, 3, 5],              // Mon, Wed, Fri
                pack:       VersePack.epistles.id,
                count:      5,
                difficulty: Difficulty.scholar.rawValue
            ),
        ]

        for a in alarms {
            let alarm = Alarm(label: a.label, hour: a.hour, minute: a.minute)
            alarm.isAM          = a.isAM
            alarm.repeatDays    = a.days
            alarm.packId        = a.pack
            alarm.questionCount = a.count
            alarm.difficultyRaw = a.difficulty
            alarm.isEnabled     = true
            context.insert(alarm)
            Task { try? await AlarmService.shared.schedule(alarm) }
        }
    }

    // MARK: - Profile

    private static func updateProfile(context: ModelContext) {
        let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        guard let profile = profiles.first else { return }

        if profile.name.isEmpty { profile.name = "Enoch" }
        profile.snoozeTaxEnabled   = true
        profile.sabbathModeEnabled = true
        profile.translationRaw     = Translation.esv.rawValue
        profile.activePackId       = VersePack.psalms.id
        profile.questionCount      = 3
    }
}
