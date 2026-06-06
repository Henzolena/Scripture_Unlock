import SwiftUI
import AVFoundation

/// Full chapter reader — verse rows. Audio is managed by the shared
/// BibleAudioPlayer injected from BibleView via the environment so it
/// keeps playing when the user navigates back to the book list.
struct BibleReaderView: View {

    let book:           BibleBook
    let chapter:        Int
    let language:       String
    /// When set, the reader scrolls to this verse number and briefly highlights it.
    var highlightVerse: Int? = nil

    // MARK: - State

    @State private var bibleChapter:    BibleChapter? = nil
    @State private var isLoading:       Bool = true
    @State private var fetchFailed:     Bool = false
    @State private var copiedVerse:     Int? = nil
    @State private var showCopiedBanner = false
    @State private var practiceTarget:  PracticeTarget? = nil
    /// The verse currently glowing — set after load, cleared after animation.
    @State private var glowingVerse:    Int? = nil

    /// Shared player — owned by BibleView, injected via .environment(audioPlayer).
    @Environment(BibleAudioPlayer.self) private var audio

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    if isLoading {
                        placeholderRows.padding(20)
                    } else if let ch = bibleChapter, !ch.verses.isEmpty {
                        verseList(ch.verses)
                            .padding(20)
                            .padding(.bottom, audio.isAvailable || audio.isLoading ? 110 : 60)
                    } else {
                        errorView
                    }
                }
                .background(DesignSystem.warmCream)
                // After chapter loads, scroll to the target verse and trigger the glow
                .onChange(of: bibleChapter) { _, ch in
                    guard let target = highlightVerse, ch != nil else { return }
                    Task { @MainActor in
                        // Brief wait for layout to complete before scrolling
                        try? await Task.sleep(for: .milliseconds(300))
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo(target, anchor: .center)
                        }
                        // Delay glow slightly so the scroll settles first
                        try? await Task.sleep(for: .milliseconds(400))
                        withAnimation(.easeIn(duration: 0.35)) { glowingVerse = target }
                        // Hold the highlight for 2.5 seconds then fade out
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation(.easeOut(duration: 0.6)) { glowingVerse = nil }
                    }
                }
            }

            // ── Copy confirmation banner ─────────────────────────────────────
            if showCopiedBanner {
                copiedBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    // Float above the persistent audio bar when it's visible
                    .padding(.bottom, audio.isAvailable ? 116 : 16)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showCopiedBanner)
        .sheet(item: $practiceTarget) { target in
            VerseQuizSheet(target: target)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
        }
        .background(DesignSystem.warmCream)
        .navigationTitle("\(book.englishName) \(chapter)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    practiceTarget = PracticeTarget(
                        book:     book,
                        chapter:  chapter,
                        language: language
                    )
                } label: {
                    AppActionLabel(
                        title: "Quiz",
                        icon: "graduationcap.fill",
                        style: .primary,
                        size: .toolbar,
                        fullWidth: false
                    )
                }
            }
        }
        .task {
            // Load verse text and audio in parallel.
            // Audio will keep playing even after navigating away from this view.
            async let textLoad: () = loadChapter()
            async let audioLoad: () = audio.load(
                language: language,
                book:     book.abbreviation,
                bookName: book.englishName,
                chapter:  chapter
            )
            _ = await (textLoad, audioLoad)
        }
        // No onDisappear stop — audio lives in the environment and persists
    }

    // MARK: - Verse list

    private func verseList(_ verses: [EthiopianVerse]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            chapterHeader
            ForEach(verses, id: \.verse) { verse in
                VerseRow(
                    verse:         verse,
                    isCopied:      copiedVerse == verse.verse,
                    isHighlighted: glowingVerse == verse.verse,
                    onCopy:        { copyVerse(verse) }
                )
                .id(verse.verse)   // anchor for ScrollViewReader.scrollTo
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
        isLoading    = true
        fetchFailed  = false
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

// MARK: - Verse row

private struct VerseRow: View {
    let verse:         EthiopianVerse
    let isCopied:      Bool
    var isHighlighted: Bool = false
    let onCopy:        () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Verse number — brighter gold when highlighted
            Text("\(verse.verse)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isHighlighted
                    ? DesignSystem.pastoralGold
                    : DesignSystem.pastoralGold.opacity(0.7))
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 32, alignment: .trailing)
                .padding(.top, 5)

            // Verse text — slightly bolder when highlighted
            Text(verse.text)
                .font(DesignSystem.serif(19))
                .foregroundStyle(isHighlighted ? DesignSystem.ink : DesignSystem.ink.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    isHighlighted
                        ? DesignSystem.pastoralGold.opacity(0.14)
                        : isCopied
                            ? DesignSystem.pastoralGold.opacity(0.08)
                            : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHighlighted
                    ? DesignSystem.pastoralGold.opacity(0.45)
                    : Color.clear,
                    lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.4) { onCopy() }
        .animation(.easeInOut(duration: 0.35), value: isHighlighted)
        .animation(.easeInOut(duration: 0.2),  value: isCopied)
    }
}
