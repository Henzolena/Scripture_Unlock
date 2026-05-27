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
//   2. AVAudioSession(.playback) + synthesised tone loop — alarm keeps
//      ringing even when screen is locked or app is backgrounded
//   3. isIdleTimerDisabled = true — screen stays on while alarm is active
//   4. Re-engagement notification — fires 4 seconds after the user backgrounds
//      the app mid-alarm, pulling them back to the trivia screen
//   5. RootView adds interactiveDismissDisabled(true) so the cover cannot
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

    // Audio engine for in-app alarm tone
    private var audioEngine   = AVAudioEngine()
    private var playerNode    = AVAudioPlayerNode()
    private var isAudioActive = false

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        setupAudioEngine()
        Task { await requestPermissions() }
    }

    // MARK: - Permissions

    private func requestPermissions() async {
        let granted = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive])
        await MainActor.run { hasNotificationPermission = granted ?? false }
    }

    // MARK: - Audio engine (synthesised alarm tone, no audio file needed)

    private func setupAudioEngine() {
        audioEngine.attach(playerNode)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
    }

    /// Starts the in-app alarm tone and loops it until stopAlarmAudio() is called.
    func startAlarmAudio() {
        guard !isAudioActive else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)

            // Build one buffer containing the full beep pattern:
            // 0.35 s high (880 Hz) + 0.25 s low (660 Hz) + 0.65 s silence
            // Then schedule it with .loops — AVAudioPlayerNode repeats it
            // indefinitely without any completion-handler chaining.
            let sampleRate: Double = 44_100
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

            let highFrames    = Int(sampleRate * 0.35)
            let lowFrames     = Int(sampleRate * 0.25)
            let silenceFrames = Int(sampleRate * 0.65)
            let totalFrames   = highFrames + lowFrames + silenceFrames

            let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                          frameCapacity: AVAudioFrameCount(totalFrames))!
            buffer.frameLength = AVAudioFrameCount(totalFrames)
            let data = buffer.floatChannelData![0]

            let amplitude: Float = 0.65
            for i in 0..<highFrames {
                data[i] = amplitude * Float(sin(2 * .pi * 880 * Double(i) / sampleRate))
            }
            for i in 0..<lowFrames {
                data[highFrames + i] = amplitude * Float(sin(2 * .pi * 660 * Double(i) / sampleRate))
            }
            // silence frames are zero-initialised by AVAudioPCMBuffer

            if !audioEngine.isRunning { try audioEngine.start() }

            // .loops makes the node repeat this buffer forever
            playerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            playerNode.play()
            isAudioActive = true
        } catch {
            // Graceful degradation — rest of alarm (visual + notifications) still works
        }

        UIApplication.shared.isIdleTimerDisabled = true
    }

    /// Stops the alarm tone and re-enables screen sleep.
    func stopAlarmAudio() {
        playerNode.stop()
        if audioEngine.isRunning { audioEngine.stop() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isAudioActive = false
        UIApplication.shared.isIdleTimerDisabled = false
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

    /// Dev/simulator: trigger the full trivia flow immediately.
    func fireTestAlarm() {
        let test = Alarm(label: "Test alarm", hour: 6, minute: 0)
        activeAlarm = test
        startAlarmAudio()
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
        content.sound              = .default
        content.interruptionLevel  = .timeSensitive
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

        let alarm            = Alarm(label: label, hour: userInfo["hour"] as? Int ?? 6,
                                     minute: userInfo["minute"] as? Int ?? 0)
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let info = notification.request.content.userInfo
        if let alarm = reconstruct(from: info) {
            let nid = info["notificationId"] as? String ?? notification.request.identifier
            Task { await MainActor.run {
                self.activeNotificationId = nid
                self.activeAlarm = alarm
                self.startAlarmAudio()
            }}
        }
        completionHandler([.sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if let alarm = reconstruct(from: info) {
            let nid = info["notificationId"] as? String ?? response.notification.request.identifier
            Task { await MainActor.run {
                self.activeNotificationId = nid
                self.activeAlarm = alarm
                self.startAlarmAudio()
            }}
        }
        completionHandler()
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let scriptureUnlockAlarmFired = Notification.Name("scriptureUnlockAlarmFired")
}
