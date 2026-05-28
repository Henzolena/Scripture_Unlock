import SwiftUI
import AVFoundation

/// Full chapter reader — verse rows + floating audio player bar.
struct BibleReaderView: View {

    let book:     BibleBook
    let chapter:  Int
    let language: String

    // MARK: - State

    @State private var bibleChapter:    BibleChapter? = nil
    @State private var isLoading:       Bool = true
    @State private var fetchFailed:     Bool = false
    @State private var copiedVerse:     Int? = nil
    @State private var showCopiedBanner = false

    /// One player instance per reader view — cleaned up on disappear.
    @State private var audio = BibleAudioPlayer()

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                if isLoading {
                    placeholderRows.padding(20)
                } else if let ch = bibleChapter, !ch.verses.isEmpty {
                    verseList(ch.verses)
                        .padding(20)
                        // Extra bottom padding so last verse clears the audio bar
                        .padding(.bottom, audio.isAvailable || audio.isLoading ? 110 : 60)
                } else {
                    errorView
                }
            }
            .background(DesignSystem.warmCream)

            // ── Audio player bar ─────────────────────────────────────────────
            if audio.isLoading || audio.isAvailable {
                AudioPlayerBar(audio: audio, book: book, chapter: chapter)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // ── Copy confirmation banner ─────────────────────────────────────
            if showCopiedBanner {
                copiedBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, audio.isAvailable ? 116 : 16)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: audio.isAvailable)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: audio.isLoading)
        .animation(.easeInOut(duration: 0.25), value: showCopiedBanner)
        .background(DesignSystem.warmCream)
        .navigationTitle("\(book.englishName) \(chapter)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Load verse text and audio in parallel
            async let textLoad: () = loadChapter()
            async let audioLoad: () = audio.load(
                language: language,
                book: book.abbreviation,
                chapter: chapter
            )
            _ = await (textLoad, audioLoad)
        }
        .onDisappear {
            audio.stop()
        }
    }

    // MARK: - Verse list

    private func verseList(_ verses: [EthiopianVerse]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            chapterHeader
            ForEach(verses, id: \.verse) { verse in
                VerseRow(verse: verse, isCopied: copiedVerse == verse.verse) {
                    copyVerse(verse)
                }
            }
        }
    }

    // MARK: - Chapter header

    private var chapterHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                Text("\(chapter)")
                    .font(.system(size: 64, weight: .black, design: .serif))
                    .foregroundStyle(DesignSystem.pastoralGold)
                    .fixedSize(horizontal: true, vertical: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(book.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(DesignSystem.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if book.name != book.englishName {
                        Text(book.englishName)
                            .font(.system(size: 13))
                            .foregroundStyle(DesignSystem.slate400)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
            }
            Rectangle()
                .fill(DesignSystem.pastoralGold.opacity(0.35))
                .frame(height: 1)
                .cornerRadius(1)
        }
        .padding(.bottom, 20)
    }

    // MARK: - Placeholder skeleton

    private var placeholderRows: some View {
        VStack(alignment: .leading, spacing: 20) {
            RoundedRectangle(cornerRadius: 8)
                .fill(DesignSystem.slate400.opacity(0.15))
                .frame(height: 72)
            ForEach(0..<8, id: \.self) { i in
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DesignSystem.pastoralGold.opacity(0.20))
                        .frame(width: 20, height: 16)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DesignSystem.slate400.opacity(0.15))
                            .frame(height: 16)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DesignSystem.slate400.opacity(0.10))
                            .frame(width: CGFloat([0.9, 0.7, 0.85, 0.6][i % 4]) * 260, height: 16)
                    }
                }
            }
        }
        .redacted(reason: .placeholder)
    }

    // MARK: - Error view

    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(DesignSystem.slate400)
            Text("Could not load \(book.englishName) \(chapter)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DesignSystem.ink)
                .multilineTextAlignment(.center)
            Text("Check your connection and go back to try again.")
                .font(.system(size: 13))
                .foregroundStyle(DesignSystem.slate400)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Copied banner

    private var copiedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(DesignSystem.bethanyGreen)
            Text("Verse copied")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignSystem.ink)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(DesignSystem.surface)
        .cornerRadius(24)
        .shadow(color: DesignSystem.shadow1, radius: 12, x: 0, y: 4)
    }

    // MARK: - Helpers

    private func loadChapter() async {
        isLoading   = true
        fetchFailed = false
        bibleChapter = await EthiopianBibleService.shared.chapter(
            book: book.abbreviation, chapter: chapter, language: language
        )
        if bibleChapter == nil { fetchFailed = true }
        isLoading = false
    }

    private func copyVerse(_ verse: EthiopianVerse) {
        UIPasteboard.general.string = "\(book.englishName) \(chapter):\(verse.verse) — \(verse.text)"
        copiedVerse = verse.verse
        withAnimation { showCopiedBanner = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showCopiedBanner = false }
            copiedVerse = nil
        }
    }
}

// MARK: - Audio player bar

private struct AudioPlayerBar: View {

    let audio:   BibleAudioPlayer
    let book:    BibleBook
    let chapter: Int

    /// True while the user is actively dragging the scrubber.
    @State private var isScrubbing   = false
    @State private var scrubPosition: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            // Thin separator line
            Rectangle()
                .fill(DesignSystem.pastoralGold.opacity(0.20))
                .frame(height: 1)

            VStack(spacing: 10) {
                // ── Top row: title + controls ────────────────────────────────
                HStack(spacing: 0) {
                    // Book / chapter label
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(book.englishName) \(chapter)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DesignSystem.ink)
                            .lineLimit(1)
                        if !audio.sourceName.isEmpty {
                            Text(audio.sourceName)
                                .font(.system(size: 10))
                                .foregroundStyle(DesignSystem.slate400)
                        }
                    }

                    Spacer()

                    if audio.isLoading {
                        // Buffering indicator
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.75)
                                .tint(DesignSystem.pastoralGold)
                            Text("Loading audio…")
                                .font(.system(size: 12))
                                .foregroundStyle(DesignSystem.slate400)
                        }
                    } else {
                        // Playback controls
                        HStack(spacing: 20) {
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
                        }
                    }
                }

                // ── Progress scrubber ────────────────────────────────────────
                if audio.isAvailable {
                    VStack(spacing: 4) {
                        // Custom progress track + Slider
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                // Track background
                                Capsule()
                                    .fill(DesignSystem.slate400.opacity(0.25))
                                    .frame(height: 3)

                                // Fill
                                Capsule()
                                    .fill(DesignSystem.pastoralGold)
                                    .frame(
                                        width: geo.size.width * CGFloat(isScrubbing ? scrubPosition : audio.progress),
                                        height: 3
                                    )

                                // Thumb
                                Circle()
                                    .fill(DesignSystem.pastoralGold)
                                    .frame(width: 12, height: 12)
                                    .shadow(color: DesignSystem.pastoralGold.opacity(0.4), radius: 4)
                                    .offset(x: geo.size.width * CGFloat(isScrubbing ? scrubPosition : audio.progress) - 6)
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

// MARK: - Verse row

private struct VerseRow: View {
    let verse:       EthiopianVerse
    let isCopied:    Bool
    let onLongPress: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(verse.verse)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DesignSystem.pastoralGold)
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 32, alignment: .trailing)
                .padding(.top, 5)

            Text(verse.text)
                .font(DesignSystem.serif(19))
                .foregroundStyle(DesignSystem.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isCopied ? DesignSystem.pastoralGold.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.4) { onLongPress() }
        .animation(.easeInOut(duration: 0.2), value: isCopied)
    }
}
