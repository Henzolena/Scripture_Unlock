import AVFoundation
import Combine
import Observation

/// Lightweight AVPlayer wrapper for streaming the Verse-of-the-Day devotional audio.
/// Intentionally simpler than BibleAudioPlayer — no scrubber, no lock-screen art,
/// just play / pause / stop for a ~60-second clip.
@Observable
final class VersOfDayAudioPlayer {

    private(set) var isPlaying:    Bool = false
    private(set) var isLoading:    Bool = false
    /// True while waiting for on-demand server generation to complete.
    private(set) var isGenerating: Bool = false

    private var player:       AVPlayer?
    private var loadedURL:    String?
    private var endObserver:  Any?
    private var pollTask:     Task<Void, Never>?

    private let requestURL = "https://ethiopian-bible-api-production.up.railway.app/api/v1/votd/request-audio"

    // MARK: - Load

    func load(url: String) {
        guard url != loadedURL else { return }
        stop()
        loadedURL = url
        guard let u = URL(string: url) else { return }

        isLoading = true
        // The audio URL includes a ?v={timestamp} cache-buster on every generation,
        // so each new clip gets a unique URL and iOS never serves a stale cached file.
        let item = AVPlayerItem(url: u)
        player   = AVPlayer(playerItem: item)

        // Observe when buffering is ready so we can clear the loading flag
        Task { @MainActor in
            for await _ in item.publisher(for: \AVPlayerItem.status).values {
                if item.status == .readyToPlay || item.status == .failed {
                    self.isLoading = false
                    break
                }
            }
        }

        // Auto-reset isPlaying when clip finishes
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
            self?.player?.seek(to: .zero)
        }

        configureAudioSession()
    }

    // MARK: - Controls

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func stop() {
        pollTask?.cancel()
        player?.pause()
        if let obs = endObserver { NotificationCenter.default.removeObserver(obs) }
        player      = nil
        loadedURL   = nil
        endObserver = nil
        pollTask    = nil
        isPlaying   = false
        isLoading   = false
        isGenerating = false
    }

    // MARK: - On-demand generation

    /// Call when user taps play but audio isn't ready yet.
    /// Triggers server-side generation, polls every 5s until ready, then auto-plays.
    /// `onVotdReady` is called on the main actor with the updated VerseOfDay so
    /// the view can refresh its state (audio_url + audio_status).
    func requestAndPlay(onVotdReady: @escaping @MainActor (VerseOfDay) -> Void) {
        guard !isGenerating else { return }
        isGenerating = true

        pollTask = Task { @MainActor in
            defer { isGenerating = false }

            // 1. Tell Railway to start generation (fire-and-forget POST)
            if let url = URL(string: requestURL) {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                _ = try? await URLSession.shared.data(for: req)
            }

            // 2. Poll until ready (max ~90 s, every 5 s)
            for _ in 0..<18 {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }

                guard let fresh = await VerseOfDayService.shared.today(),
                      fresh.audioStatus == "ready",
                      let audioURL = fresh.audioURL else { continue }

                // 3. Notify the view, load, and play
                onVotdReady(fresh)
                load(url: audioURL)
                togglePlayPause()
                return
            }
            // Timed out — leave isGenerating = false, user can tap again
        }
    }

    // MARK: - Private

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}
