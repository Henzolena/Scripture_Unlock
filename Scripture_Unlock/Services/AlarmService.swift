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

    private var activeNotificationId: String?

    // MARK: - Audio engine (for keep-alive) + AVAudioPlayer (for alarm tone)
    private var audioEngine      = AVAudioEngine()
    private var playerNode       = AVAudioPlayerNode()
    private var alarmPlayer: AVAudioPlayer?   // plays the selected .caf tone
    private var isAlarmAudioActive  = false   // loud alarm is playing
    private var isKeepAliveActive   = false   // silent keep-alive is playing

    // MARK: - Background monitoring
    private var backgroundTimer: Timer?
    private var monitoredAlarm: Alarm?   // the alarm the timer is armed for

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        setupAudioEngine()
        Task { await requestPermissions() }
    }

    // MARK: - Permissions

    private func requestPermissions() async {
        let granted = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        await MainActor.run { hasNotificationPermission = granted ?? false }
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

        // Find the soonest upcoming alarm
        let upcoming = alarms
            .compactMap { alarm -> (alarm: Alarm, date: Date)? in
                guard let d = alarm.nextActualFireDate else { return nil }
                return (alarm, d)
            }
            .sorted { $0.date < $1.date }
            .first
        guard let next = upcoming else {
            print("[AlarmService] No upcoming alarms — skipping background monitoring")
            return
        }

        let delay = next.date.timeIntervalSinceNow
        guard delay > 0 else { return }

        monitoredAlarm = next.alarm
        startKeepAlive()

        // Timer fires at alarm time and triggers everything
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
            content.sound             = UNNotificationSound(named: UNNotificationSoundName(rawValue: "alarm_ringtone.caf"))
            if content.sound == nil { content.sound = .default }
            content.interruptionLevel = .timeSensitive
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
                identifier: "alarm-fire-\(alarm.id.uuidString)",
                content:    content,
                trigger:    trigger
            )
            try? await UNUserNotificationCenter.current().add(request)
            print("[AlarmService] Fired from background: \(alarm.label)")
        }
    }

    // MARK: - Re-engagement (fires when user backs out of alarm screen)

    /// Schedule a loud pull-back notification 4 seconds from now.
    /// Called by RootView's scenePhase observer when the app is backgrounded
    /// while an alarm is active.
    func scheduleReengagementNotification() {
        let content = UNMutableNotificationContent()
        content.title            = "\u{1F514} Alarm still ringing!"
        content.body             = "Return to Scripture Unlock to answer your verses."
        content.sound            = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 4, repeats: false)
        let request = UNNotificationRequest(
            identifier: "reengagement",
            content:    content,
            trigger:    trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    func cancelReengagementNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["reengagement"])
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

    /// Called by TriviaViewModel after all correct answers — fully silences the alarm.
    func dismissAlarm(_ alarm: Alarm) async {
        stopBackgroundMonitoring()
        stopAlarmAudio()
        cancelReengagementNotification()

        var ids = allIdentifiers(for: alarm)
        if let nid = activeNotificationId { ids.append(nid) }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)

        await MainActor.run {
            activeAlarm          = nil
            activeNotificationId = nil
        }
    }

    // MARK: - Private helpers

    private func dayIdentifier(alarm: Alarm, day: Int) -> String {
        "\(alarm.id.uuidString)-day\(day)"
    }

    private func allIdentifiers(for alarm: Alarm) -> [String] {
        var ids = [alarm.id.uuidString]
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
