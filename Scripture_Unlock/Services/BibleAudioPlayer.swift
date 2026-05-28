import Foundation
import AVFoundation
import MediaPlayer

// MARK: - BibleAudioPlayer
//
// @Observable AVPlayer wrapper for streaming Bible chapter audio with full
// background playback support (lock screen, Control Center, CarPlay, AirPlay).
//
// Background playback flow
// ────────────────────────
//  • UIBackgroundModes "audio" is declared in Info.plist — iOS keeps the app
//    alive while audio is playing.
//  • MPRemoteCommandCenter handles play/pause/skip from lock screen buttons,
//    headphone remotes, CarPlay, and the Control Center transport bar.
//  • MPNowPlayingInfoCenter keeps the lock screen metadata in sync
//    (title, artist, duration, elapsed time, artwork).
//
// Usage
// ─────
//  1. Call load(language:book:bookName:chapter:) — checks coverage cache,
//     sets up AVPlayer with the 307-redirect stream URL.
//  2. Observe isAvailable / isPlaying / progress / duration from SwiftUI.
//  3. Call stop() when the reader view disappears.

@Observable
final class BibleAudioPlayer {

    // MARK: - Observable state

    /// True while coverage lookup or AVPlayer is buffering.
    private(set) var isLoading   = false
    /// True once AVPlayer is readyToPlay and the book has audio.
    private(set) var isAvailable = false
    /// Mirrors AVPlayer playback state.
    private(set) var isPlaying   = false
    /// Current playback position in seconds.
    private(set) var currentTime: Double = 0
    /// Total duration in seconds (0 until AVPlayer resolves it).
    private(set) var duration:    Double = 0
    /// Human-readable audio source (e.g. "Internet Archive — English NIV Audio Bible").
    private(set) var sourceName:  String = ""

    /// 0.0 → 1.0 progress, safe to bind to a progress slider.
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(currentTime / duration, 1.0)
    }

    // MARK: - Private

    private let baseURL = "https://ethiopian-bible-api-production.up.railway.app/api/v1"

    @ObservationIgnored private var player:            AVPlayer?
    @ObservationIgnored private var timeObserver:      Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver:       NSObjectProtocol?
    @ObservationIgnored private var loadedKey          = ""

    // Now Playing metadata — updated on every load / play / pause / time tick
    @ObservationIgnored private var nowPlayingTitle    = ""
    @ObservationIgnored private var nowPlayingArtist   = ""

    // MARK: - Init / deinit

    init() {
        configureAudioSession()
        registerRemoteCommands()
    }

    deinit {
        unregisterRemoteCommands()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Public API

    /// Load audio for the given chapter.
    /// - Parameters:
    ///   - bookName: Localized book name shown on the lock screen (e.g. "John").
    func load(
        language:  String,
        book abbreviation: String,
        bookName:  String,
        chapter:   Int
    ) async {
        let key = "\(language)-\(abbreviation)-\(chapter)"
        guard key != loadedKey else { return }

        await MainActor.run {
            stop(keepKey: false)
            isLoading   = true
            isAvailable = false
            sourceName  = ""
            loadedKey   = key
        }

        // ── 1. Coverage lookup (cached — zero extra network cost) ────────────
        let cov     = await EthiopianBibleService.shared.coverage(language: language)
        let bookCov = cov?.bookIndex[abbreviation.uppercased()]

        guard bookCov?.audio == true else {
            await MainActor.run { isLoading = false }
            return
        }

        if let src = cov?.audio.source, !src.isEmpty {
            await MainActor.run { sourceName = src }
        }

        // ── 2. Prepare Now Playing metadata ─────────────────────────────────
        nowPlayingTitle  = "\(bookName) \(chapter)"
        nowPlayingArtist = sourceName.isEmpty ? "Holy Bible" : sourceName

        // ── 3. Build stream URL (API 307-redirects to the actual mp3) ────────
        let audioPath = "\(baseURL)/\(language)/audio/\(abbreviation)/\(chapter)"
        guard let audioURL = URL(string: audioPath) else {
            await MainActor.run { isLoading = false }
            return
        }

        await MainActor.run {
            setupPlayer(url: audioURL)
        }
    }

    func togglePlayPause() { isPlaying ? pause() : play() }

    func play() {
        player?.play()
        isPlaying = true
        updateNowPlaying(rate: 1)
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlaying(rate: 0)
    }

    /// Seek to a normalised position (0.0 – 1.0).
    func seek(to fraction: Double) {
        guard duration > 0, let player else { return }
        let secs = max(0, min(fraction * duration, duration))
        player.seek(
            to: CMTime(seconds: secs, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter:  .zero
        )
        currentTime = secs
        updateNowPlaying(rate: isPlaying ? 1 : 0)
    }

    /// Skip forward or backward by `seconds`.
    func skip(by seconds: Double) {
        seek(to: (currentTime + seconds) / max(duration, 1))
    }

    /// Full stop — clears AVPlayer and Now Playing info.
    func stop(keepKey: Bool = false) {
        player?.pause()
        removeObservers()
        player      = nil
        isPlaying   = false
        isAvailable = false
        currentTime = 0
        duration    = 0
        if !keepKey { loadedKey = "" }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - AVPlayer setup

    @MainActor
    private func setupPlayer(url: URL) {
        let item = AVPlayerItem(url: url)
        let p    = AVPlayer(playerItem: item)
        player   = p

        // Status observation — readyToPlay triggers Now Playing + auto-play
        statusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    let d = item.duration.seconds
                    if d.isFinite && d > 0 { self.duration = d }
                    self.isLoading   = false
                    self.isAvailable = true
                    self.publishNowPlaying()
                case .failed:
                    self.isLoading   = false
                    self.isAvailable = false
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
                default:
                    break
                }
            }
        }

        // Periodic time observer — syncs progress + lock screen elapsed time
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            if time.seconds.isFinite { self.currentTime = time.seconds }
            if let d = self.player?.currentItem?.duration.seconds, d.isFinite && d > 0 {
                self.duration = d
            }
            // Keep lock screen elapsed time in sync (cheap dict update)
            if self.isPlaying {
                MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = self.currentTime
            }
        }

        // Playback-ended notification
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object:  item,
            queue:   .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isPlaying   = false
            self.currentTime = self.duration
            self.updateNowPlaying(rate: 0)
        }
    }

    // MARK: - Now Playing

    /// Publish the full Now Playing dictionary (called once when readyToPlay).
    private func publishNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle:                   nowPlayingTitle,
            MPMediaItemPropertyArtist:                  nowPlayingArtist,
            MPMediaItemPropertyAlbumTitle:              "Holy Bible",
            MPMediaItemPropertyPlaybackDuration:        duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate:        isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]

        // Bible scroll artwork — use SF Symbol rendered into UIImage
        if let artwork = makeArtwork() {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Lightweight update — only rate + elapsed time (no artwork re-render).
    private func updateNowPlaying(rate: Double) {
        guard MPNowPlayingInfoCenter.default().nowPlayingInfo != nil else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate]        = rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration]         = duration
    }

    /// Render a simple bible-scroll SF Symbol as the lock screen artwork.
    private func makeArtwork() -> MPMediaItemArtwork? {
        let size = CGSize(width: 600, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            // Warm cream background
            UIColor(red: 0.98, green: 0.96, blue: 0.91, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Gold bible icon
            let config = UIImage.SymbolConfiguration(pointSize: 300, weight: .medium)
            if let symbol = UIImage(systemName: "book.closed.fill", withConfiguration: config)?
                .withTintColor(UIColor(red: 0.73, green: 0.56, blue: 0.19, alpha: 1),
                               renderingMode: .alwaysOriginal) {
                let x = (size.width  - symbol.size.width)  / 2
                let y = (size.height - symbol.size.height) / 2
                symbol.draw(at: CGPoint(x: x, y: y))
            }
        }
        return MPMediaItemArtwork(boundsSize: size) { _ in image }
    }

    // MARK: - Remote Command Center

    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        // Play
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            guard let self, self.isAvailable else { return .noActionableNowPlayingItem }
            self.play()
            return .success
        }

        // Pause
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.isAvailable else { return .noActionableNowPlayingItem }
            self.pause()
            return .success
        }

        // Toggle play/pause (headphone button, CarPlay steering wheel)
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, self.isAvailable else { return .noActionableNowPlayingItem }
            self.togglePlayPause()
            return .success
        }

        // Skip back 15 s
        center.skipBackwardCommand.isEnabled          = true
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self, self.isAvailable else { return .noActionableNowPlayingItem }
            self.skip(by: -15)
            return .success
        }

        // Skip forward 15 s
        center.skipForwardCommand.isEnabled          = true
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in
            guard let self, self.isAvailable else { return .noActionableNowPlayingItem }
            self.skip(by: 15)
            return .success
        }

        // Seek (dragging the lock screen progress bar)
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  self.isAvailable,
                  let e = event as? MPChangePlaybackPositionCommandEvent
            else { return .noActionableNowPlayingItem }
            let fraction = e.positionTime / max(self.duration, 1)
            self.seek(to: fraction)
            return .success
        }

        // Disable commands that don't apply (no next/previous chapter from here)
        center.nextTrackCommand.isEnabled     = false
        center.previousTrackCommand.isEnabled = false
    }

    private func unregisterRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.skipBackwardCommand.removeTarget(nil)
        center.skipForwardCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
    }

    // MARK: - Observers cleanup

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
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: []        // no mixing — take full audio focus
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[BibleAudioPlayer] AVAudioSession error: \(error)")
        }
    }
}
