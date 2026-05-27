import Foundation
import UserNotifications

// MARK: - AlarmService
//
// AlarmKit (iOS 26) requires Apple entitlement approval before it can be used:
//   developer.apple.com/contact/request/notifications-critical-alerts-entitlement
//
// Until approved, this service:
//   - Schedules alarms via UNUserNotificationCenter (standard notifications)
//   - Exposes fireTestAlarm() so the full trivia UI can be tested immediately
//
// When AlarmKit is approved:
//   1. Add the AlarmKit capability in Target → Signing & Capabilities
//   2. Replace the UNUserNotificationCenter scheduling below with ALAlarmManager calls

@Observable
final class AlarmService {

    static let shared = AlarmService()

    /// The alarm currently ringing (nil = nothing active).
    var activeAlarm: Alarm?

    /// Whether the app has notification permission.
    var hasCriticalAlertsPermission = false

    private init() {
        Task { await requestPermissions() }
    }

    // MARK: - Permissions

    private func requestPermissions() async {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(
            options: [.alert, .sound, .badge]
        )
        hasCriticalAlertsPermission = granted ?? false
    }

    // MARK: - Scheduling (UNUserNotificationCenter fallback)

    func schedule(_ alarm: Alarm) async throws {
        let content = UNMutableNotificationContent()
        content.title = alarm.label
        content.body = "Answer \(alarm.effectiveQuestionCount) verses to silence."
        content.sound = .defaultCritical

        let comps = DateComponents(
            hour: alarm.isAM ? alarm.hour : alarm.hour + 12,
            minute: alarm.minute
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: !alarm.repeatDays.isEmpty)

        let request = UNNotificationRequest(
            identifier: alarm.id.uuidString,
            content: content,
            trigger: trigger
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    func rescheduleAll(_ alarms: [Alarm]) async {
        for alarm in alarms where alarm.isEnabled {
            try? await schedule(alarm)
        }
    }

    func cancel(_ alarm: Alarm) async {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [alarm.id.uuidString])
    }

    /// Called by TriviaViewModel after all correct answers — silences the alarm.
    func dismissAlarm(_ alarm: Alarm) async {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [alarm.id.uuidString])
        await MainActor.run { activeAlarm = nil }
    }

    /// Simulator / dev testing: triggers the full trivia flow immediately.
    func fireTestAlarm() {
        let test = Alarm(label: "Test alarm", hour: 6, minute: 0)
        activeAlarm = test
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let scriptureUnlockAlarmFired = Notification.Name("scriptureUnlockAlarmFired")
}
