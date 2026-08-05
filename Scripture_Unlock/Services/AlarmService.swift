import Foundation
import UserNotifications
import AVFoundation
import UIKit

// MARK: - AlarmService
//
// AlarmKit (iOS 26) requires Apple entitlement approval. Until approved:
//
//  Aggressiveness layer (mirrors what Alarmy/Step Out of Bed do):
//   1. .timeSensitive interruption level — cuts through most Focus modes
//   2. Background audio keep-alive — when app goes to background, a silent
//      PCM buffer starts looping under UIBackgroundModes:audio so the app
//      stays running and its Timer fires at the exact alarm moment.
//   3. AVAudioSession(.playback) + synthesised tone loop — alarm keeps
//      ringing even when screen is locked or app is backgrounded
//   4. In-process alarm timer — fires at the scheduled time and:
//        a) Switches from silent keep-alive → full alarm audio
//        b) Sets activeAlarm (SwiftUI fullScreenCover shows on next foreground)
//        c) Posts an immediate UNNotification so a banner / lock-screen
//           alert appears even if the user is in another app
//   5. isIdleTimerDisabled = true — screen stays on while alarm is active
//   6. Re-engagement notification — fires 4 seconds after the user backgrounds
//      the app mid-alarm, pulling them back to the trivia screen
//   7. RootView adds interactiveDismissDisabled(true) so the cover cannot
//      be swiped away
//
//  Hard limits without AlarmKit:
//   - Cannot bypass the ringer/silent switch (Critical Alerts entitlement
//     is not granted to alarm/lifestyle apps by Apple)
//   - Cannot prevent force-quit (iOS design; same limitation as Alarmy)
//   - True lock-screen takeover only possible with AlarmKit entitlement

@Observable
final class AlarmService: NSObject {

    static let shared = AlarmService()

    /// Alarm currently ringing (nil = nothing active).
    var activeAlarm: Alarm?
    /// Whether the app has been granted notification permission.
    var hasNotificationPermission = false
    /// True when the active alarm was triggered via AlarmKit (system already rang it;
    /// RingingView should skip in-app audio).
    var alarmTriggeredByAlarmKit = false

    private var activeNotificationId: String?

    /// Resolves an alarm id to the live SwiftData object. Set once by RootView.
    ///
    /// Without this, alarms arriving via a notification were rebuilt from userInfo
    /// into a detached copy that dropped `repeatDays` and `snoozeCountToday`. That
    /// meant the snooze question penalty silently vanished, `dismissAlarm` cleared
    /// the penalty on a throwaway object so the real alarm kept it forever, and the
    /// AlarmKit repeat-schedule restore never ran.
    var alarmResolver: ((UUID) -> Alarm?)?

    /// Leave headroom under iOS's 64-pending-notification cap. Past the limit iOS
    /// silently keeps only the soonest requests and drops the rest with no error,
    /// so a user with many repeating alarms would lose them without warning.
    private let notificationRequestBudget = 56

    // MARK: - Audio engine (for keep-alive) + AVAudioPlayer (for alarm tone)
    private var audioEngine      = AVAudioEngine()
    private var playerNode       = AVAudioPlayerNode()
    private var alarmPlayer: AVAudioPlayer?   // plays the selected .caf tone
    private var isAlarmAudioActive  = false   // loud alarm is playing
    private var isKeepAliveActive   = false   // silent keep-alive is playing

    // MARK: - Background monitoring
    private var backgroundTimer: Timer?
    private var monitoredAlarm: Alarm?    // the alarm the timer is armed for
    private var monitoredAlarms: [Alarm] = []  // full set, so the timer can re-arm

    /// Start the silent keep-alive only when an alarm is this close.
    private static let keepAliveWindow: TimeInterval = 30 * 60

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        setupAudioEngine()
        // Deliberately does NOT prompt here. Constructing the singleton used to
        // fire the system permission dialog during launch, before onboarding had
        // explained why an alarm app needs notifications — and a denial here
        // breaks the core feature. RootView calls requestPermissions() once the
        // user has a profile instead.
    }

    // MARK: - Permissions

    /// Requests notification + AlarmKit authorization. Safe to call repeatedly:
    /// iOS only shows the dialog on the first request.
    func requestPermissions() async {
        let granted = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        await MainActor.run { hasNotificationPermission = granted ?? false }
        if #available(iOS 26, *) {
            _ = await requestAlarmKitAuthorization()
        }
    }

    // MARK: - Audio engine (synthesised alarm tone, no audio file needed)

    private func setupAudioEngine() {
        audioEngine.attach(playerNode)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
    }

    /// Starts the loud alarm tone using the alarm's selected .caf sound file.
    /// Falls back to a synthesised PCM beep if the file is missing.
    /// If silent keep-alive is running it is replaced first.
    func startAlarmAudio() {
        if isKeepAliveActive { stopKeepAlive() }
        guard !isAlarmAudioActive else { return }
        do {
            // Interrupt any other audio so the alarm cuts through
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)

            // Determine which tone file to play
            let toneId   = activeAlarm?.toneIdentifier ?? AlarmTone.all[0].id
            let tone     = AlarmTone.find(id: toneId)
            let cafName  = tone.filename + ".caf"

            if let url = Bundle.main.url(forResource: tone.filename, withExtension: "caf") {
                // Play the real .caf file, looping indefinitely
                alarmPlayer = try AVAudioPlayer(contentsOf: url)
                alarmPlayer?.numberOfLoops = -1   // infinite loop
                alarmPlayer?.volume = 1.0
                alarmPlayer?.play()
            } else {
                // Fallback: synthesised PCM beep via AVAudioEngine
                print("[AlarmService] Missing \(cafName) — using synthesised fallback")
                try startSynthesisedFallback()
            }
            isAlarmAudioActive = true
        } catch {
            print("[AlarmService] startAlarmAudio error: \(error)")
        }
        UIApplication.shared.isIdleTimerDisabled = true
    }

    /// Synthesised PCM fallback used only when a .caf file is unexpectedly missing.
    private func startSynthesisedFallback() throws {
        let sampleRate: Double = 44_100
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let highFrames    = Int(sampleRate * 0.35)
        let lowFrames     = Int(sampleRate * 0.25)
        let silenceFrames = Int(sampleRate * 0.65)
        let totalFrames   = highFrames + lowFrames + silenceFrames
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames))!
        buffer.frameLength = AVAudioFrameCount(totalFrames)
        let data = buffer.floatChannelData![0]
        let amp: Float = 0.85
        for i in 0..<highFrames {
            data[i] = amp * Float(sin(2 * .pi * 880 * Double(i) / sampleRate))
        }
        for i in 0..<lowFrames {
            data[highFrames + i] = amp * Float(sin(2 * .pi * 660 * Double(i) / sampleRate))
        }
        if !audioEngine.isRunning { try audioEngine.start() }
        playerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        playerNode.play()
    }

    /// Stops the alarm tone and re-enables screen sleep.
    func stopAlarmAudio() {
        alarmPlayer?.stop()
        alarmPlayer = nil
        playerNode.stop()
        if audioEngine.isRunning { audioEngine.stop() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isAlarmAudioActive = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Silent keep-alive (holds UIBackgroundModes:audio session open)

    /// Plays an inaudible buffer to keep the app running in background via
    /// UIBackgroundModes:audio so the background alarm timer can fire on time.
    private func startKeepAlive() {
        guard !isAlarmAudioActive, !isKeepAliveActive else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let sampleRate: Double = 44_100
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
            // 5-second silent buffer, looped — inaudible but keeps session alive
            let frames  = Int(sampleRate * 5)
            let buffer  = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
            buffer.frameLength = AVAudioFrameCount(frames)
            // All samples default to 0.0 (silence)
            if !audioEngine.isRunning { try audioEngine.start() }
            playerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            playerNode.play()
            isKeepAliveActive = true
            print("[AlarmService] Silent keep-alive started")
        } catch {
            print("[AlarmService] startKeepAlive error: \(error)")
        }
    }

    private func stopKeepAlive() {
        guard isKeepAliveActive else { return }
        playerNode.stop()
        // Don't stop the engine here — startAlarmAudio may restart it immediately
        isKeepAliveActive = false
        print("[AlarmService] Silent keep-alive stopped")
    }

    // MARK: - Background monitoring

    /// Call this when the app goes to background.
    /// Starts a silent audio keep-alive + schedules an in-process Timer so the
    /// alarm fires even if the user is in another app or the phone is locked.
    func startBackgroundMonitoring(alarms: [Alarm]) {
        stopBackgroundMonitoring()          // cancel any previous timer
        guard activeAlarm == nil else { return }  // already ringing — no-op

        monitoredAlarms = alarms
        armNextBackgroundTimer()
    }

    /// Arms a timer for the soonest upcoming alarm in `monitoredAlarms`.
    ///
    /// Re-armed after each fire so a second alarm later in the same background
    /// stretch is still driven in-process — previously only the first one was, and
    /// everything after it depended solely on notifications.
    private func armNextBackgroundTimer() {
        backgroundTimer?.invalidate()
        backgroundTimer = nil

        let upcoming = monitoredAlarms
            .compactMap { alarm -> (alarm: Alarm, date: Date)? in
                guard let d = alarm.nextActualFireDate else { return nil }
                return (alarm, d)
            }
            .sorted { $0.date < $1.date }
            .first

        guard let next = upcoming else {
            print("[AlarmService] No upcoming alarms — skipping background monitoring")
            stopKeepAlive()
            return
        }

        let delay = next.date.timeIntervalSinceNow
        guard delay > 0 else { return }

        monitoredAlarm = next.alarm

        // Only hold the audio session open when an alarm is actually near. Running
        // a silent buffer indefinitely is both a battery cost and the pattern App
        // Review guideline 2.5.4 targets (background audio must be audible
        // content). Beyond this window the scheduled notification is the mechanism.
        if delay <= Self.keepAliveWindow {
            startKeepAlive()
        } else {
            stopKeepAlive()
            print("[AlarmService] Next alarm in \(Int(delay))s — keep-alive deferred")
        }

        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.fireFromBackground(next.alarm)
        }
        RunLoop.main.add(timer, forMode: .common)
        backgroundTimer = timer

        print("[AlarmService] Background monitoring armed: '\(next.alarm.label)' in \(Int(delay))s")
    }

    /// Call this when the app returns to the foreground.
    func stopBackgroundMonitoring() {
        backgroundTimer?.invalidate()
        backgroundTimer   = nil
        monitoredAlarm    = nil
        monitoredAlarms   = []
        stopKeepAlive()
    }

    /// Fires the alarm from inside a background timer callback.
    private func fireFromBackground(_ alarm: Alarm) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.monitoredAlarm = nil
            self.activeAlarm    = alarm
            self.startAlarmAudio()

            // Post an immediate notification so a banner / lock-screen alert
            // appears even if the user is looking at a different app.
            let content = UNMutableNotificationContent()
            content.title             = "⏰ \(alarm.label)"
            content.body              = "Answer \(alarm.effectiveQuestionCount) Bible verses to silence the alarm."
            // Use the alarm's own tone. This previously named "alarm_ringtone.caf",
            // which is not in the bundle — and because UNNotificationSound(named:)
            // is non-optional the nil-check below it never fired, so iOS silently
            // played nothing and the user's tone choice was ignored.
            content.sound             = AlarmTone.find(id: alarm.toneIdentifier).notificationSound
            content.interruptionLevel = .timeSensitive
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
                identifier: "alarm-fire-\(alarm.id.uuidString)",
                content:    content,
                trigger:    trigger
            )
            try? await UNUserNotificationCenter.current().add(request)
            print("[AlarmService] Fired from background: \(alarm.label)")

            // Re-arm for any later alarm in this background stretch.
            self.armNextBackgroundTimer()
        }
    }

    // MARK: - Re-engagement (fires when user backs out of alarm screen)

    /// Schedules three escalating notifications after the user backgrounds
    /// the app mid-alarm. Each fires independently so even if the user
    /// dismisses the first two, the third still pulls them back.
    func scheduleReengagementNotification() {
        let escalation: [(TimeInterval, String)] = [
            (4,   "Return to Scripture Unlock to answer your verses."),
            (45,  "Your alarm is still going. Answer your Bible verses to silence it."),
            (180, "Still haven't finished? Your devotion verses are waiting.")
        ]
        for (i, (delay, body)) in escalation.enumerated() {
            let content = UNMutableNotificationContent()
            content.title             = "\u{1F514} Alarm still ringing!"
            content.body              = body
            content.sound             = .default
            content.interruptionLevel = .timeSensitive
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            let request = UNNotificationRequest(
                identifier: "reengagement-\(i)",
                content:    content,
                trigger:    trigger
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    func cancelReengagementNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["reengagement-0", "reengagement-1", "reengagement-2"])
    }

    /// Restarts alarm audio when the app returns to foreground while an alarm
    /// is active but audio was not playing (e.g. backgrounded before audio started).
    func restartAlarmAudioIfNeeded() {
        guard activeAlarm != nil, !isAlarmAudioActive else { return }
        startAlarmAudio()
    }

    // MARK: - Scheduling

    func schedule(_ alarm: Alarm) async throws {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: allIdentifiers(for: alarm))

        let h24 = alarm.isAM ? alarm.hour : alarm.hour + 12

        if alarm.repeatDays.isEmpty {
            var comps   = DateComponents()
            comps.hour   = h24
            comps.minute = alarm.minute
            comps.second = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(
                identifier: alarm.id.uuidString,
                content:    makeContent(alarm: alarm, notificationId: alarm.id.uuidString),
                trigger:    trigger
            )
            try await center.add(request)
        } else {
            // One notification request per selected weekday
            // Model: 0=Sun…6=Sat; Calendar weekday: 1=Sun…7=Sat
            for day in alarm.repeatDays {
                let notifId = dayIdentifier(alarm: alarm, day: day)
                var comps   = DateComponents()
                comps.weekday = day + 1
                comps.hour    = h24
                comps.minute  = alarm.minute
                comps.second  = 0
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                let request = UNNotificationRequest(
                    identifier: notifId,
                    content:    makeContent(alarm: alarm, notificationId: notifId),
                    trigger:    trigger
                )
                try await center.add(request)
            }
        }

        // iOS 26+: additionally schedule a system-level AlarmKit alarm that
        // wakes the screen, plays through silent mode, and shows a fullscreen UI.
        if #available(iOS 26, *) { await scheduleWithAlarmKit(alarm) }
    }

    func rescheduleAll(_ alarms: [Alarm]) async {
        // Schedule soonest-first and stop at the request budget. A repeating alarm
        // costs one request per selected weekday, so ~9 weekday alarms alone would
        // exceed the 64-request cap and iOS would start dropping them silently.
        let enabled = alarms
            .filter { $0.isEnabled }
            .compactMap { alarm -> (alarm: Alarm, date: Date)? in
                guard let d = alarm.nextActualFireDate else { return nil }
                return (alarm, d)
            }
            .sorted { $0.date < $1.date }

        var spent = 0
        for (alarm, _) in enabled {
            // Reset the snooze penalty unless this alarm is currently ringing —
            // resetting mid-quiz would change the question count under the user.
            if alarm.id != activeAlarm?.id {
                alarm.snoozeCountToday = 0
            }

            let cost = max(1, alarm.repeatDays.count)
            guard spent + cost <= notificationRequestBudget else {
                print("""
                [AlarmService] Notification budget reached (\(spent)/\(notificationRequestBudget)) \
                — '\(alarm.label)' and any later alarms rely on AlarmKit only
                """)
                break
            }
            spent += cost
            try? await schedule(alarm)
        }
    }

    func cancel(_ alarm: Alarm) async {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: allIdentifiers(for: alarm))
        if #available(iOS 26, *) { cancelWithAlarmKit(alarm) }
    }

    /// Schedules a plain notification for a snoozed alarm.
    ///
    /// Snooze previously rescheduled only through AlarmKit. That entitlement still
    /// requires Apple approval, so on any device where it is unavailable the snooze
    /// silently never rang again and the user overslept. This is the fallback path.
    func scheduleSnoozeFallback(for alarm: Alarm, fireDate: Date) async {
        let delay = fireDate.timeIntervalSinceNow
        guard delay > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title             = "⏰ \(alarm.label)"
        content.body              = "Snooze over — answer \(alarm.effectiveQuestionCount) verses to silence the alarm."
        content.sound             = AlarmTone.find(id: alarm.toneIdentifier).notificationSound
        content.interruptionLevel = .timeSensitive
        content.userInfo          = makeContent(alarm: alarm, notificationId: snoozeIdentifier(for: alarm)).userInfo

        let request = UNNotificationRequest(
            identifier: snoozeIdentifier(for: alarm),
            content:    content,
            trigger:    UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
        print("[AlarmService] Snooze fallback notification armed in \(Int(delay))s")
    }

    func snoozeIdentifier(for alarm: Alarm) -> String {
        "snooze-\(alarm.id.uuidString)"
    }

    /// Called by TriviaViewModel after all correct answers — fully silences the alarm.
    func dismissAlarm(_ alarm: Alarm) async {
        stopBackgroundMonitoring()
        stopAlarmAudio()
        cancelReengagementNotification()

        var ids = allIdentifiers(for: alarm)
        if let nid = activeNotificationId { ids.append(nid) }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)

        // Capture before reset — used below to decide whether to restore repeat schedule
        let hadSnooze = alarm.snoozeCountToday > 0

        await MainActor.run {
            alarm.snoozeCountToday   = 0  // Reset daily penalty for next ring
            activeAlarm              = nil
            activeNotificationId     = nil
            alarmTriggeredByAlarmKit = false
        }

        // If snooze was used, AlarmKit's original repeating schedule was replaced by a
        // one-shot .fixed alarm. Restore the regular repeat schedule now that the quiz
        // is complete so the alarm fires correctly next time.
        if hadSnooze, #available(iOS 26, *) {
            await scheduleWithAlarmKit(alarm)
        }
    }

    // MARK: - Private helpers

    private func dayIdentifier(alarm: Alarm, day: Int) -> String {
        "\(alarm.id.uuidString)-day\(day)"
    }

    private func allIdentifiers(for alarm: Alarm) -> [String] {
        var ids = [alarm.id.uuidString, snoozeIdentifier(for: alarm)]
        ids += (0..<7).map { dayIdentifier(alarm: alarm, day: $0) }
        return ids
    }

    private func makeContent(alarm: Alarm, notificationId: String) -> UNMutableNotificationContent {
        let content                = UNMutableNotificationContent()
        content.title              = alarm.label
        content.body               = "Answer \(alarm.effectiveQuestionCount) verses to silence."
        content.interruptionLevel  = .timeSensitive
        // Use the alarm's selected tone (.caf file in the app bundle)
        let tone = AlarmTone.find(id: alarm.toneIdentifier)
        content.sound = tone.notificationSound
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
            "toneIdentifier": alarm.toneIdentifier,
        ]
        return content
    }

    private func reconstruct(from userInfo: [AnyHashable: Any]) -> Alarm? {
        guard
            let idStr = userInfo["alarmId"] as? String,
            let id    = UUID(uuidString: idStr),
            let label = userInfo["alarmLabel"] as? String
        else { return nil }

        // Prefer the live SwiftData object so repeatDays and snoozeCountToday are
        // real. Only fall back to rebuilding from userInfo if it cannot be found.
        if let live = alarmResolver?(id) { return live }

        let alarm              = Alarm(label: label, hour: userInfo["hour"] as? Int ?? 6,
                                       minute: userInfo["minute"] as? Int ?? 0)
        alarm.id               = id
        alarm.isAM             = (userInfo["isAM"] as? Int ?? 1) == 1
        alarm.questionCount    = userInfo["questionCount"]  as? Int    ?? 3
        alarm.packId           = userInfo["packId"]         as? String ?? ""
        alarm.difficultyRaw    = userInfo["difficultyRaw"]  as? String ?? Difficulty.regular.rawValue
        alarm.translationRaw   = userInfo["translationRaw"] as? String ?? Translation.esv.rawValue
        alarm.toneIdentifier   = userInfo["toneIdentifier"] as? String ?? AlarmTone.all[0].id
        return alarm
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AlarmService: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let info = notification.request.content.userInfo

        // Alarm-fire notification triggered by fireFromBackground — app is already showing
        // the full-screen cover, so suppress the banner and just play the badge.
        if notification.request.identifier.hasPrefix("alarm-fire-") {
            completionHandler([.badge])
            return
        }

        // Re-engagement or scheduled system notification: set activeAlarm if not already ringing
        if activeAlarm == nil, let alarm = reconstruct(from: info) {
            let nid = info["notificationId"] as? String ?? notification.request.identifier
            Task { @MainActor in
                self.activeNotificationId = nid
                self.activeAlarm          = alarm
                self.startAlarmAudio()
            }
        }
        // Suppress the banner — the full-screen cover handles the visual alarm
        completionHandler([.sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo

        // User tapped a notification (from lock screen or banner) — bring up the alarm screen
        if activeAlarm == nil {
            // For alarm-fire notifications there's no userInfo alarm data — use monitoredAlarm
            if response.notification.request.identifier.hasPrefix("alarm-fire-"),
               let alarm = monitoredAlarm ?? activeAlarm {
                Task { @MainActor in
                    self.activeAlarm = alarm
                    self.startAlarmAudio()
                }
            } else if let alarm = reconstruct(from: info) {
                let nid = info["notificationId"] as? String ?? response.notification.request.identifier
                Task { @MainActor in
                    self.activeNotificationId = nid
                    self.activeAlarm          = alarm
                    self.startAlarmAudio()
                }
            }
        }
        completionHandler()
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let scriptureUnlockAlarmFired = Notification.Name("scriptureUnlockAlarmFired")
}
