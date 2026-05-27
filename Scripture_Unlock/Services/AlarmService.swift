import Foundation
import UserNotifications

// AlarmKit is a system framework added in iOS 26.
// To enable it: Target → Signing & Capabilities → + → AlarmKit
// Until the capability is added this guard keeps the rest of the app buildable.
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Wraps AlarmKit. Only correct trivia answers may call dismissAlarm().
/// All other dismissal paths are handled by AlarmKit's system persistence.
@Observable
final class AlarmService {

    static let shared = AlarmService()

    /// The alarm currently ringing (nil = nothing active).
    var activeAlarm: Alarm?

    /// Whether the app has Critical Alerts permission.
    var hasCriticalAlertsPermission = false

    private init() {
        Task { await requestPermissions() }
        observeAlarmEvents()
    }

    // MARK: - Permissions

    private func requestPermissions() async {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(
            options: [.alert, .sound, .badge, .criticalAlert]
        )
        hasCriticalAlertsPermission = granted ?? false
    }

    // MARK: - Scheduling

    func schedule(_ alarm: Alarm) async throws {
#if canImport(AlarmKit)
        let attributes = ALAlarmAttributes(
            title: alarm.label,
            body: "Answer \(alarm.effectiveQuestionCount) verses to silence.",
            sound: ALAlarmSound(named: alarm.toneIdentifier),
            style: .countdown
        )

        let schedule: ALAlarmSchedule
        if alarm.repeatDays.isEmpty {
            schedule = .once(at: alarm.nextFireDate)
        } else {
            let weekdays = alarm.repeatDays.map { $0 + 1 }
            schedule = .weekly(on: weekdays, at: DateComponents(
                hour: alarm.isAM ? alarm.hour : alarm.hour + 12,
                minute: alarm.minute
            ))
        }

        let request = ALAlarmRequest(
            identifier: alarm.id.uuidString,
            attributes: attributes,
            schedule: schedule
        )
        try await ALAlarmManager.shared.add(request)
#endif
    }

    func rescheduleAll(_ alarms: [Alarm]) async {
        for alarm in alarms where alarm.isEnabled {
            try? await schedule(alarm)
        }
    }

    func cancel(_ alarm: Alarm) async {
#if canImport(AlarmKit)
        await ALAlarmManager.shared.removePendingAlarmRequests(
            withIdentifiers: [alarm.id.uuidString]
        )
#endif
    }

    /// ONLY path to silence — called by TriviaViewModel after all correct answers.
    func dismissAlarm(_ alarm: Alarm) async {
#if canImport(AlarmKit)
        await ALAlarmManager.shared.dismissAlarm(withIdentifier: alarm.id.uuidString)
#endif
        await MainActor.run { activeAlarm = nil }
    }

    /// Simulator / dev testing: fires the trivia flow immediately without AlarmKit.
    func fireTestAlarm() {
        let test = Alarm(label: "Test alarm", hour: 6, minute: 0)
        activeAlarm = test
    }

    // MARK: - Observe incoming alarms

    private func observeAlarmEvents() {
#if canImport(AlarmKit)
        NotificationCenter.default.addObserver(
            forName: .ALAlarmDidFire,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let alarmId = notification.userInfo?["identifier"] as? String,
                  let uuid = UUID(uuidString: alarmId) else { return }
            NotificationCenter.default.post(
                name: .scriptureUnlockAlarmFired,
                object: nil,
                userInfo: ["alarmId": uuid]
            )
        }
#endif
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let scriptureUnlockAlarmFired = Notification.Name("scriptureUnlockAlarmFired")
}
