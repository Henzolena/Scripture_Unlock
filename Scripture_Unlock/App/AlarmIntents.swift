import AppIntents
import Foundation
import AlarmKit

// MARK: - AlarmKit Metadata (iOS 26+)
// Stored with each scheduled alarm so a future Widget Extension can display
// alarm details without fetching from SwiftData.

@available(iOS 26, *)
nonisolated struct ScriptureAlarmMetadata: AlarmMetadata, Codable, Hashable, Sendable {
    var alarmId: String
    var label: String
    var questionCount: Int
    var packId: String
    var difficultyRaw: String
    var translationRaw: String
}

// MARK: - Start Devotion
// Bound to the stop action on the lock-screen alarm (via AlarmConfiguration.stopIntent).
// Writes alarmId to UserDefaults; openAppWhenRun brings the app to foreground.

struct StartDevotionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Devotion"
    static var openAppWhenRun: Bool { true }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Alarm ID")
    var alarmId: String

    init() { alarmId = "" }
    init(alarmId: String) { self.alarmId = alarmId }

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(alarmId, forKey: "pendingAlarmKitAlarmId")
        return .result()
    }
}

// MARK: - Snooze (+1 question penalty)
// Bound to the secondary action (AlarmConfiguration.secondaryIntent).

struct SnoozeAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Snooze"
    // KNOWN UX WART, deliberately left as-is for now: tapping snooze foregrounds
    // the app, which is the opposite of what a snoozing user wants.
    //
    // It cannot simply be flipped to false. All the snooze work — incrementing
    // snoozeCountToday and rescheduling both AlarmKit and the notification
    // fallback — currently happens in checkPendingAlarmKitAlarm(), which only runs
    // when the app becomes active. With this false, the intent would write its
    // UserDefaults key and nothing would reschedule, so the snooze would never
    // ring at all. Silently oversleeping is far worse than an app launch.
    //
    // Proper fix: move the reschedule into perform() so it runs without the app
    // foregrounding. That needs on-device verification against an approved
    // AlarmKit entitlement, which is still pending.
    static var openAppWhenRun: Bool { true }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Alarm ID")
    var alarmId: String

    init() { alarmId = "" }
    init(alarmId: String) { self.alarmId = alarmId }

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(alarmId, forKey: "snoozedAlarmKitAlarmId")
        return .result()
    }
}
