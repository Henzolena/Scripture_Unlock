import AlarmKit
import AppIntents
import SwiftUI

// The app's SwiftData model is also named 'Alarm', so we alias AlarmKit's Alarm
// to avoid ambiguity everywhere in this file.
private typealias AKAlarm = AlarmKit.Alarm

@available(iOS 26, *)
extension AlarmService {

    // MARK: - Authorization

    func requestAlarmKitAuthorization() async -> Bool {
        switch AlarmManager.shared.authorizationState {
        case .notDetermined:
            let state = try? await AlarmManager.shared.requestAuthorization()
            return state == .authorized
        case .authorized:
            return true
        default:
            return false
        }
    }

    // MARK: - Schedule

    /// Schedules an alarm via AlarmKit.
    /// - Parameters:
    ///   - alarm: The SwiftData alarm to schedule.
    ///   - snoozeFireDate: When non-nil, schedules a one-shot snooze at this exact date
    ///     instead of computing the next regular fire date. Bypasses the `isEnabled`
    ///     and `nextActualFireDate` checks since the alarm is already active.
    func scheduleWithAlarmKit(_ alarm: Alarm, snoozeFireDate: Date? = nil) async {
        guard await requestAlarmKitAuthorization() else { return }

        // cancel() is synchronous in AlarmKit — not async
        try? AlarmManager.shared.cancel(id: alarm.id)

        let fireDate: Date
        if let snooze = snoozeFireDate {
            fireDate = snooze
        } else {
            guard alarm.isEnabled, let d = alarm.nextActualFireDate else { return }
            fireDate = d
        }

        let h24 = alarm.isAM ? alarm.hour : alarm.hour + 12

        // Lock-screen button label for the secondary (snooze) action.
        // The primary stop action uses the system default dismiss UI (iOS 26.1+).
        let snoozeButton = AlarmButton(
            text: "Snooze (+1 question)",
            textColor: .white,
            systemImageName: "clock"
        )

        let alert = Self.makeAlert(
            title: LocalizedStringResource(stringLiteral: alarm.label),
            snoozeButton: snoozeButton
        )

        let metadata = ScriptureAlarmMetadata(
            alarmId: alarm.id.uuidString,
            label: alarm.label,
            questionCount: alarm.effectiveQuestionCount,  // includes any snooze penalty
            packId: alarm.packId,
            difficultyRaw: alarm.difficultyRaw,
            translationRaw: alarm.translationRaw
        )

        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: metadata,
            tintColor: Color(red: 0.85, green: 0.68, blue: 0.27)
        )

        // Build the schedule. Snooze is always one-shot (.fixed) regardless of
        // repeat days — it fires once at the snooze time, then the normal repeat
        // schedule resumes on the next regular alarm trigger.
        let schedule: AKAlarm.Schedule
        if snoozeFireDate != nil || alarm.repeatDays.isEmpty {
            schedule = .fixed(fireDate)
        } else {
            let time = AKAlarm.Schedule.Relative.Time(hour: h24, minute: alarm.minute)
            let weekdays: [Locale.Weekday] = alarm.repeatDays.compactMap { day in
                switch day {
                case 0: return .sunday
                case 1: return .monday
                case 2: return .tuesday
                case 3: return .wednesday
                case 4: return .thursday
                case 5: return .friday
                case 6: return .saturday
                default: return nil
                }
            }
            let recurrence = AKAlarm.Schedule.Relative.Recurrence.weekly(weekdays)
            schedule = .relative(AKAlarm.Schedule.Relative(time: time, repeats: recurrence))
        }

        // Intents go on the configuration — AlarmButton is visual only
        let startIntent = StartDevotionIntent(alarmId: alarm.id.uuidString)
        let snoozeIntent = SnoozeAlarmIntent(alarmId: alarm.id.uuidString)

        let config = AlarmManager.AlarmConfiguration.alarm(
            schedule: schedule,
            attributes: attributes,
            stopIntent: startIntent,
            secondaryIntent: snoozeIntent
        )

        _ = try? await AlarmManager.shared.schedule(id: alarm.id, configuration: config)

        // SnoozeAlarmIntent runs without SwiftData, so leave it what it needs to
        // build the snooze notification on its own.
        AlarmService.cacheAlarmMetadata(alarm)

        print("[AlarmKit] Scheduled '\(alarm.label)' → \(fireDate)")
    }

    // MARK: - Alert construction (runtime-compatible)

    /// Builds the lock-screen alert using the `stopButton:` initialiser.
    ///
    /// This looks like the wrong choice — that parameter is deprecated from iOS
    /// 26.1 with "stopButton is deprecated and will no longer be used", so the
    /// value is ignored and the system default dismiss UI is shown instead. It is
    /// deliberate, because it is the only form present in *every* 26.x runtime.
    ///
    /// The modern `init(title:secondaryButton:secondaryButtonBehavior:)` is
    /// annotated `@available(iOS 26.1, *)`, which equals this app's deployment
    /// target — so it is strongly linked, not weak-imported (0 of 44 AlarmKit
    /// symbol references are weak). Any 26.1 runtime that predates the final API
    /// therefore fails to bind it and dyld aborts the process *at launch*, before
    /// any code runs, which no `#available` check can guard. The 26.1 simulator
    /// runtime shipped with Xcode 26.2 (build 23B5059e, a pre-release seed) is
    /// exactly such a runtime: it exports only the `stopButton:` form.
    ///
    /// Using the deprecated initialiser costs nothing at runtime on 26.1+ and
    /// keeps the app launchable everywhere. Revisit once the minimum supported
    /// runtime is known to post-date the reshape.
    ///
    /// The enclosing method carries a matching `@available(..., deprecated:)`
    /// annotation so the deprecation warning is suppressed at this one call site
    /// rather than project-wide.
    @available(iOS, deprecated: 26.1, message: "Intentionally uses the stopButton initialiser for 26.1 runtime compatibility")
    private static func makeAlert(
        title: LocalizedStringResource,
        snoozeButton: AlarmButton
    ) -> AlarmPresentation.Alert {
        // Ignored on 26.1+, used by pre-release 26.1 runtimes where it is required.
        let stopButton = AlarmButton(
            text: "Open",
            textColor: .white,
            systemImageName: "book.fill"
        )
        return AlarmPresentation.Alert(
            title: title,
            stopButton: stopButton,
            secondaryButton: snoozeButton,
            secondaryButtonBehavior: .custom
        )
    }

    // MARK: - Cancel (synchronous in AlarmKit)

    func cancelWithAlarmKit(_ alarm: Alarm) {
        try? AlarmManager.shared.cancel(id: alarm.id)
    }

    // MARK: - Handle foreground entry after AlarmKit dismissal

    /// Called when the scene becomes active. Reads UserDefaults keys written by
    /// StartDevotionIntent / SnoozeAlarmIntent and activates the matching alarm.
    ///
    /// Processing order matters: handle snooze FIRST. The background in-process timer
    /// and AlarmKit fire simultaneously, so `activeAlarm` may already be set (and the
    /// in-app notification may already say "N verses") when the snooze intent arrives.
    /// We must clear that stale state so the user gets their requested rest period.
    func checkPendingAlarmKitAlarm(alarms: [Alarm]) {

        // STEP 1 — Reconcile any snoozes taken on the lock screen.
        //
        // SnoozeAlarmIntent already armed the next ring itself, so this must never
        // schedule a *new* snooze window. Doing so was the trap that made
        // openAppWhenRun=false unsafe: the intent's own notification opens the app,
        // which would see the leftover key and push the alarm out another 5 minutes,
        // forever. Here we only charge the banked penalty and, if the snooze has not
        // fired yet, upgrade it to a real AlarmKit alarm for the lock-screen UI.
        if let snoozedId = UserDefaults.standard.string(forKey: "snoozedAlarmKitAlarmId"),
           let alarm = alarms.first(where: { $0.id.uuidString == snoozedId }) {

            let idString = alarm.id.uuidString
            UserDefaults.standard.removeObject(forKey: "snoozedAlarmKitAlarmId")

            // Apply every snooze the intent banked while the app was closed.
            let pending = AlarmService.pendingSnoozeCount(idString)
            if pending > 0 {
                alarm.snoozeCountToday += pending
                UserDefaults.standard.removeObject(forKey: AlarmService.SnoozeKeys.pendingCount(idString))
                AlarmService.cacheAlarmMetadata(alarm)   // keep the cached count honest
            }

            let snoozeFireDate = UserDefaults.standard.object(
                forKey: AlarmService.SnoozeKeys.fireDate(idString)) as? Date

            // Only touch the schedule while the snooze is still in the future.
            if let fireDate = snoozeFireDate, fireDate > Date() {
                // Also clear the stop key — the user chose snooze, not stop.
                if UserDefaults.standard.string(forKey: "pendingAlarmKitAlarmId") == idString {
                    UserDefaults.standard.removeObject(forKey: "pendingAlarmKitAlarmId")
                }
                Task { await scheduleWithAlarmKit(alarm, snoozeFireDate: fireDate) }

                // If the in-process timer fired simultaneously and put the quiz on
                // screen, respect the snooze and take it back down.
                if activeAlarm?.id == alarm.id {
                    stopAlarmAudio()
                    UNUserNotificationCenter.current().removeDeliveredNotifications(
                        withIdentifiers: ["alarm-fire-\(idString)"]
                    )
                    activeAlarm = nil
                    alarmTriggeredByAlarmKit = false
                }
                return   // resting until the snooze fires
            }

            // Snooze already elapsed: fall through so the alarm can present.
            UserDefaults.standard.removeObject(forKey: AlarmService.SnoozeKeys.fireDate(idString))
        }

        // STEP 2 — User slid to stop the lock-screen alarm; show the quiz.
        guard activeAlarm == nil else { return }
        if let pendingId = UserDefaults.standard.string(forKey: "pendingAlarmKitAlarmId"),
           let alarm = alarms.first(where: { $0.id.uuidString == pendingId }) {
            UserDefaults.standard.removeObject(forKey: "pendingAlarmKitAlarmId")
            alarmTriggeredByAlarmKit = true
            activeAlarm = alarm
        }
    }
}
