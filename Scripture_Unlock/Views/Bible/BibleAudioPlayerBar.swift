import SwiftUI

/// Persistent floating audio player bar shown at the bottom of the Bible tab.
/// Lives in BibleView so it survives navigation between book list, chapter grid,
/// and reader screens. The user must explicitly tap ✕ to dismiss it.
struct BibleAudioPlayerBar: View {

    let audio: BibleAudioPlayer

    @State private var isScrubbing    = false
    @State private var scrubPosition: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            // ── Thin gold separator ──────────────────────────────────────────
            Rectangle()
                .fill(DesignSystem.pastoralGold.opacity(0.20))
                .frame(height: 1)

            VStack(spacing: 10) {
                // ── Top row ──────────────────────────────────────────────────
                HStack(spacing: 0) {

                    // Title + source
                    VStack(alignment: .leading, spacing: 2) {
                        Text(audio.displayTitle.isEmpty ? "Holy Bible" : audio.displayTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DesignSystem.ink)
                            .lineLimit(1)
                        if !audio.sourceName.isEmpty {
                            Text(audio.sourceName)
                                .font(.system(size: 10))
                                .foregroundStyle(DesignSystem.slate400)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if audio.isLoading {
                        // ── Buffering ────────────────────────────────────────
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.75)
                                .tint(DesignSystem.pastoralGold)
                            Text("Loading audio…")
                                .font(.system(size: 12))
                                .foregroundStyle(DesignSystem.slate400)
                        }
                    } else {
                        // ── Playback controls ────────────────────────────────
                        HStack(spacing: 16) {

                            // Skip back 15 s
                            Button { audio.skip(by: -15) } label: {
                                Image(systemName: "gobackward.15")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(DesignSystem.slate600)
                            }

                            // Play / Pause
                            Button { audio.togglePlayPause() } label: {
                                ZStack {
                                    Circle()
                                        .fill(DesignSystem.pastoralGold)
                                        .frame(width: 44, height: 44)
                                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(DesignSystem.deepBlue)
                                        .offset(x: audio.isPlaying ? 0 : 1.5)
                                }
                            }

                            // Skip forward 15 s
                            Button { audio.skip(by: 15) } label: {
                                Image(systemName: "goforward.15")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(DesignSystem.slate600)
                            }

                            // ── Close / dismiss ──────────────────────────────
                            Button {
                                withAnimation { audio.stop() }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(DesignSystem.slate400.opacity(0.12))
                                        .frame(width: 30, height: 30)
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(DesignSystem.slate600)
                                }
                            }
                        }
                    }
                }

                // ── Progress scrubber (only when audio is fully ready) ────────
                if audio.isAvailable {
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                // Track
                                Capsule()
                                    .fill(DesignSystem.slate400.opacity(0.25))
                                    .frame(height: 3)

                                // Fill
                                Capsule()
                                    .fill(DesignSystem.pastoralGold)
                                    .frame(
                                        width: geo.size.width * CGFloat(
                                            isScrubbing ? scrubPosition : audio.progress
                                        ),
                                        height: 3
                                    )

                                // Thumb
                                Circle()
                                    .fill(DesignSystem.pastoralGold)
                                    .frame(width: 12, height: 12)
                                    .shadow(color: DesignSystem.pastoralGold.opacity(0.4), radius: 4)
                                    .offset(x: geo.size.width * CGFloat(
                                        isScrubbing ? scrubPosition : audio.progress
                                    ) - 6)
                            }
                            .frame(height: 12)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        isScrubbing   = true
                                        scrubPosition = max(0, min(value.location.x / geo.size.width, 1.0))
                                    }
                                    .onEnded { value in
                                        let pos = max(0, min(value.location.x / geo.size.width, 1.0))
                                        audio.seek(to: pos)
                                        isScrubbing = false
                                    }
                            )
                        }
                        .frame(height: 12)

                        // Time labels
                        HStack {
                            Text(formatTime(isScrubbing ? scrubPosition * audio.duration : audio.currentTime))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(DesignSystem.slate400)
                            Spacer()
                            Text(formatTime(audio.duration))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(DesignSystem.slate400)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(
            DesignSystem.surface
                .shadow(color: DesignSystem.shadow1, radius: 16, x: 0, y: -4)
        )
        .animation(.easeInOut(duration: 0.2), value: audio.isPlaying)
        .animation(.easeInOut(duration: 0.2), value: audio.isAvailable)
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let mins  = total / 60
        let secs  = total % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}
