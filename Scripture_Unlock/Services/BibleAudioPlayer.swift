import Foundation
import AVFoundation

// MARK: - BibleAudioPlayer
//
// @Observable AVPlayer wrapper for streaming Bible chapter audio.
//
// Flow
// ────
//  1. Caller passes language + book abbreviation + chapter number.
//  2. We hit the /info endpoint first — lightweight JSON check for availability.
//     If the API returns non-200 (or no audio for this combination), isAvailable
//     stays false and nothing more happens.
//  3. If available, we build the streaming URL (/audio/{book}/{chapter}) and hand
//     it to AVPlayer. The API issues a 307 redirect; AVPlayer follows it
//     automatically — the audio streams directly from j-e-c.org / archive.org /
//     ESV, no bandwidth cost on your Railway server.
//  4. Caller observes isAvailable / isPlaying / progress / duration from SwiftUI.
//
// Coverage (as of API docs)
//   Amharic  — Full Bible, missing Malachi & Luke
//   Oromo    — New Testament only (27 books)
//   Tigrinya — New Testament only (27 books)
//   English  — Full Bible (ESV audio)

@Observable
final class BibleAudioPlayer {

    // MARK: - Observable state

    /// True while checking the /info endpoint or while AVPlayer is buffering.
    private(set) var isLoading   = false
    /// True once AVPlayer status == .readyToPlay and audio exists for this chapter.
    private(set) var isAvailable = false
    /// Mirrors AVPlayer playback state.
    private(set) var isPlaying   = false
    /// Current playback position in seconds.
    private(set) var currentTime: Double = 0
    /// Total duration in seconds (0 until AVPlayer resolves it).
    private(set) var duration:    Double = 0
    /// Human-readable source name parsed from /info JSON (e.g. "ESV Audio").
    private(set) var sourceName:  String = ""

    /// 0.0 → 1.0 progress, safe to bind to a Slider.
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(currentTime / duration, 1.0)
    }

    // MARK: - Private

    private let baseURL = "https://ethiopian-bible-api-production.up.railway.app/api/v1"
    private let session = URLSession.shared

    private var player:            AVPlayer?
    private var timeObserver:      Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver:       NSObjectProtocol?
    /// Composite key of the currently loaded audio so we skip re-loading the same chapter.
    private var loadedKey = ""

    // MARK: - Init

    init() {
        configureAudioSession()
    }

    // MARK: - Public API

    /// Load audio for the given chapter. Safe to call on every view appear — no-op
    /// if the same chapter is already loaded.
    func load(language: String, book abbreviation: String, chapter: Int) async {
        let key = "\(language)-\(abbreviation)-\(chapter)"
        guard key != loadedKey else { return }

        // Reset state for new chapter
        await MainActor.run {
            stop(keepKey: false)
            isLoading  = true
            isAvailable = false
            sourceName  = ""
            loadedKey   = key
        }

        // ── 1. Check availability via /info ─────────────────────────────────
        let infoPath = "\(baseURL)/\(language)/audio/\(abbreviation)/\(chapter)/info"
        guard let infoURL = URL(string: infoPath) else {
            await MainActor.run { isLoading = false }
            return
        }

        do {
            let (data, response) = try await session.data(from: infoURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                await MainActor.run { isLoading = false }
                return
            }
            // Parse optional source name from the info JSON
            if let json   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let source = json["source"] as? String {
                await MainActor.run { sourceName = source }
            }
        } catch {
            await MainActor.run { isLoading = false }
            return
        }

        // ── 2. Build streaming URL (API issues 307 → actual file) ────────────
        let audioPath = "\(baseURL)/\(language)/audio/\(abbreviation)/\(chapter)"
        guard let audioURL = URL(string: audioPath) else {
            await MainActor.run { isLoading = false }
            return
        }

        await MainActor.run {
            setupPlayer(url: audioURL)
        }
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func play() {
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    /// Seek to a normalised position (0.0 – 1.0).
    func seek(to fraction: Double) {
        guard duration > 0, let player else { return }
        let secs = max(0, min(fraction * duration, duration))
        let time = CMTime(seconds: secs, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = secs
    }

    /// Skip forward / backward by `seconds`.
    func skip(by seconds: Double) {
        seek(to: (currentTime + seconds) / max(duration, 1))
    }

    /// Full stop — clears all state. Call when navigating away from the reader.
    func stop(keepKey: Bool = false) {
        player?.pause()
        removeObservers()
        player      = nil
        isPlaying   = false
        isAvailable = false
        currentTime = 0
        duration    = 0
        if !keepKey { loadedKey = "" }
    }

    // MARK: - AVPlayer setup

    @MainActor
    private func setupPlayer(url: URL) {
        let item = AVPlayerItem(url: url)
        let p    = AVPlayer(playerItem: item)
        player   = p

        // Observe AVPlayerItem.status for readyToPlay / failed
        statusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    let d = item.duration.seconds
                    if d.isFinite && d > 0 { self.duration = d }
                    self.isLoading  = false
                    self.isAvailable = true
                case .failed:
                    self.isLoading  = false
                    self.isAvailable = false
                default:
                    break
                }
            }
        }

        // Periodic time update (every 0.5 s)
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            if time.seconds.isFinite { self.currentTime = time.seconds }
            // Duration can arrive late for streaming sources
            if let d = self.player?.currentItem?.duration.seconds, d.isFinite && d > 0 {
                self.duration = d
            }
        }

        // Playback ended
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object:  item,
            queue:   .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isPlaying   = false
            self.currentTime = self.duration
        }
    }

    private func removeObservers() {
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
    }

    // MARK: - Audio session

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[BibleAudioPlayer] AVAudioSession error: \(error)")
        }
    }
}
