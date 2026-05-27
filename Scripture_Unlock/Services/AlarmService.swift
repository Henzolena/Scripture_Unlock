import Foundation
import UserNotifications

// MARK: - AlarmService
//
// AlarmKit (iOS 26) requires Apple entitlement approval before it can be used.
// Until approved, this service uses UNUserNotificationCenter as a fallback:
//   - Schedules one notification per selected repeat day (so Mon-Fri-only alarms
//     don't also fire Sat/Sun)
//   - Implements UNUserNotificationCenterDelegate so that when the notification
//     fires, activeAlarm is set and RootView shows RingingView
//   - One-shot alarms schedule a single fire; repeat alarms keep re-firing weekly
//
// When AlarmKit entitlement is approved:
//   1. Add the AlarmKit capability in Target → Signing & Capabilities
//   2. Replace UNUserNotificationCenter scheduling below with ALAlarmManager calls

@Observable
final class AlarmService: NSObject {

    static let shared = AlarmService()

    /// The alarm currently ringing (nil = nothing active).
    var activeAlarm: Alarm?

    /// Whether the app has notification permission.
    var hasCriticalAlertsPermission = false

    /// Identifier of the notification that fired (used for precise dismissal).
    private var activeNotificationId: String?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        Task { await requestPermissions() }
    }

    // MARK: - Permissions

    private func requestPermissions() async {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(
            options: [.alert, .sound, .badge]
        )
        await MainActor.run { hasCriticalAlertsPermission = granted ?? false }
    }

    // MARK: - Scheduling

    func schedule(_ alarm: Alarm) async throws {
        let center = UNUserNotificationCenter.current()

        // Remove any existing requests for this alarm before rescheduling
        center.removePendingNotificationRequests(withIdentifiers: allIdentifiers(for: alarm))

        let h24 = alarm.isAM ? alarm.hour : alarm.hour + 12

        if alarm.repeatDays.isEmpty {
            // One-shot: fire at the next occurrence of this clock time
            var comps = DateComponents()
            comps.hour   = h24
            comps.minute = alarm.minute
            comps.second = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request  = UNNotificationRequest(
                identifier: alarm.id.uuidString,
                content:    makeContent(alarm: alarm, notificationId: alarm.id.uuidString),
                trigger:    trigger
            )
            try await center.add(request)
        } else {
            // Repeat: one request per selected weekday
            // Our model: 0=Sun … 6=Sat; Calendar weekday: 1=Sun … 7=Sat
            for day in alarm.repeatDays {
                let notifId = dayIdentifier(alarm: alarm, day: day)
                var comps   = DateComponents()
                comps.weekday = day + 1
                comps.hour    = h24
                comps.minute  = alarm.minute
                comps.second  = 0
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                let request  = UNNotificationRequest(
                    identifier: notifId,
                    content:    makeContent(alarm: alarm, notificationId: notifId),
                    trigger:    trigger
                )
                try await center.add(request)
            }
        }
    }

    func rescheduleAll(_ alarms: [Alarm]) async {
        for alarm in alarms where alarm.isEnabled {
            try? await schedule(alarm)
        }
    }

    func cancel(_ alarm: Alarm) async {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: allIdentifiers(for: alarm))
    }

    /// Called by TriviaViewModel after all correct answers — silences the alarm.
    func dismissAlarm(_ alarm: Alarm) async {
        let center = UNUserNotificationCenter.current()
        // Remove the exact notification that fired (by stored id) and any fallback
        var ids = allIdentifiers(for: alarm)
        if let nid = activeNotificationId { ids.append(nid) }
        center.removeDeliveredNotifications(withIdentifiers: ids)
        await MainActor.run {
            activeAlarm = nil
            activeNotificationId = nil
        }
    }

    /// Simulator / dev testing: triggers the full trivia flow immediately.
    func fireTestAlarm() {
        let test = Alarm(label: "Test alarm", hour: 6, minute: 0)
        activeAlarm = test
    }

    // MARK: - Helpers

    private func dayIdentifier(alarm: Alarm, day: Int) -> String {
        "\(alarm.id.uuidString)-day\(day)"
    }

    private func allIdentifiers(for alarm: Alarm) -> [String] {
        var ids = [alarm.id.uuidString]
        ids += (0..<7).map { dayIdentifier(alarm: alarm, day: $0) }
        return ids
    }

    private func makeContent(alarm: Alarm, notificationId: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = alarm.label
        content.body  = "Answer \(alarm.effectiveQuestionCount) verses to silence."
        content.sound = .default
        // Store metadata so the alarm can be reconstructed when the app is
        // backgrounded or killed at notification delivery time.
        content.userInfo = [
            "alarmId":        alarm.id.uuidString,
            "notificationId": notificationId,
            "alarmLabel":     alarm.label,
            "hour":           alarm.hour,
            "minute":         alarm.minute,
            "isAM":           alarm.isAM ? 1 : 0,
            "questionCount":  alarm.questionCount,
            "packId":         alarm.packId,
            "difficultyRaw":  alarm.difficultyRaw,
            "translationRaw": alarm.translationRaw,
        ]
        return content
    }

    private func reconstruct(from userInfo: [AnyHashable: Any]) -> Alarm? {
        guard
            let idStr = userInfo["alarmId"] as? String,
            let id    = UUID(uuidString: idStr),
            let label = userInfo["alarmLabel"] as? String
        else { return nil }

        let alarm            = Alarm(
            label:  label,
            hour:   userInfo["hour"]   as? Int ?? 6,
            minute: userInfo["minute"] as? Int ?? 0
        )
        alarm.id             = id
        alarm.isAM           = (userInfo["isAM"] as? Int ?? 1) == 1
        alarm.questionCount  = userInfo["questionCount"]  as? Int    ?? 3
        alarm.packId         = userInfo["packId"]         as? String ?? ""
        alarm.difficultyRaw  = userInfo["difficultyRaw"]  as? String ?? Difficulty.regular.rawValue
        alarm.translationRaw = userInfo["translationRaw"] as? String ?? Translation.esv.rawValue
        return alarm
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AlarmService: UNUserNotificationCenterDelegate {

    /// App is in the foreground when the notification fires.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let info = notification.request.content.userInfo
        if let alarm = reconstruct(from: info) {
            let nid = info["notificationId"] as? String ?? notification.request.identifier
            Task { await MainActor.run {
                activeNotificationId = nid
                activeAlarm = alarm
            }}
        }
        // Suppress the banner — RingingView is already showing
        completionHandler([.sound, .badge])
    }

    /// User tapped the notification banner (app was backgrounded or killed).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if let alarm = reconstruct(from: info) {
            let nid = info["notificationId"] as? String ?? response.notification.request.identifier
            Task { await MainActor.run {
                activeNotificationId = nid
                activeAlarm = alarm
            }}
        }
        completionHandler()
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let scriptureUnlockAlarmFired = Notification.Name("scriptureUnlockAlarmFired")
}
