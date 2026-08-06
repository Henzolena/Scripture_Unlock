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
    // Does NOT foreground the app. Someone tapping snooze wants to put the phone
    // down, so perform() arms the next ring itself rather than depending on the
    // app becoming active.
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Alarm ID")
    var alarmId: String

    init() { alarmId = "" }
    init(alarmId: String) { self.alarmId = alarmId }

    func perform() async throws -> some IntentResult {
        // Charge the +1 question penalty later — SwiftData is not reachable here,
        // so bank it and let the app apply it on next launch.
        AlarmService.recordPendingSnooze(alarmId)

        // Arm the next ring now. This is the part that must not depend on the app
        // launching: it works with no AlarmKit authorization and no foreground.
        await AlarmService.scheduleSnoozeNotificationFromIntent(alarmId: alarmId)

        // Still record the id so the app can upgrade the pending snooze to a real
        // AlarmKit alarm (lock-screen UI) if it happens to open before it fires.
        UserDefaults.standard.set(alarmId, forKey: "snoozedAlarmKitAlarmId")
        return .result()
    }
}
