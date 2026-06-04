import Foundation
import AVFoundation
import UserNotifications

// MARK: - AlarmTone

/// One of the 10 selectable alarm sounds bundled with the app.
/// The `filename` matches the .caf file in Resources/Sounds/.
struct AlarmTone: Identifiable, Equatable {
    let id:          String   // used as toneIdentifier on Alarm
    let filename:    String   // without extension — matches *.caf in bundle
    let displayName: String   // shown in the picker
    let emoji:       String   // visual accent in the picker row
    let description: String   // short description of the sound character

    /// Notification sound object ready to pass to UNNotificationContent.
    var notificationSound: UNNotificationSound {
        UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(filename).caf"))
    }

    // MARK: - All tones

    static let all: [AlarmTone] = [
        AlarmTone(
            id: "alarm_digital_pure",
            filename: "alarm_digital_pure",
            displayName: "Digital Pure",
            emoji: "📳",
            description: "Clean 884 Hz digital beep"
        ),
        AlarmTone(
            id: "alarm_beep_close",
            filename: "alarm_beep_close",
            displayName: "Classic Beep",
            emoji: "⏰",
            description: "Classic alarm clock beeping"
        ),
        AlarmTone(
            id: "alarm_clock_1",
            filename: "alarm_clock_1",
            displayName: "Alarm Clock",
            emoji: "🕰️",
            description: "Traditional alarm clock ring"
        ),
        AlarmTone(
            id: "alarm_clock_2",
            filename: "alarm_clock_2",
            displayName: "Loud Clock",
            emoji: "🔔",
            description: "Loud persistent alarm ring"
        ),
        AlarmTone(
            id: "alarm_clock_3",
            filename: "alarm_clock_3",
            displayName: "Morning Bell",
            emoji: "🛎️",
            description: "Crisp morning alarm bell"
        ),
        AlarmTone(
            id: "alarm_personal",
            filename: "alarm_personal",
            displayName: "Personal Alert",
            emoji: "📢",
            description: "Personal safety alarm tone"
        ),
        AlarmTone(
            id: "alarm_air_raid",
            filename: "alarm_air_raid",
            displayName: "Air Raid",
            emoji: "🚨",
            description: "Urgent rising siren"
        ),
        AlarmTone(
            id: "alarm_siren_loop",
            filename: "alarm_siren_loop",
            displayName: "Siren",
            emoji: "🔊",
            description: "Short looping siren blast"
        ),
        AlarmTone(
            id: "alarm_siren_fade",
            filename: "alarm_siren_fade",
            displayName: "Wailing Siren",
            emoji: "🌊",
            description: "Long rising-and-falling siren"
        ),
        AlarmTone(
            id: "alarm_church_bell",
            filename: "alarm_church_bell",
            displayName: "Church Bell",
            emoji: "⛪",
            description: "Deep resonant church bell"
        ),
    ]

    static func find(id: String) -> AlarmTone {
        all.first { $0.id == id } ?? all[0]
    }
}

// MARK: - Preview player

/// Plays a short preview of an AlarmTone using AVAudioPlayer.
@Observable
final class TonePreviewPlayer {
    static let shared = TonePreviewPlayer()
    private init() {}

    private var player: AVAudioPlayer?
    private(set) var playingId: String?

    func preview(_ tone: AlarmTone) {
        stop()
        guard let url = Bundle.main.url(forResource: tone.filename, withExtension: "caf") else {
            print("[TonePreviewPlayer] Missing bundle file: \(tone.filename).caf")
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
            playingId = tone.id
        } catch {
            print("[TonePreviewPlayer] Error: \(error)")
        }
    }

    func stop() {
        player?.stop()
        player    = nil
        playingId = nil
    }
}
