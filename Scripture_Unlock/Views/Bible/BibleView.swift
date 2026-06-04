import SwiftUI
import SwiftData

/// Root of the Bible tab.
/// Owns the shared BibleAudioPlayer for the entire tab so audio survives
/// navigation (back to book list, chapter grid, etc.) until the user
/// explicitly closes it or a new chapter starts.
struct BibleView: View {

    // MARK: - Init

    init() {}

    // MARK: - State

    @Query private var profiles: [UserProfile]
    @Environment(NavigationRouter.self) private var router
    @State private var selectedLanguage: String = "am"
    @State private var books: [BibleBook] = []
    @State private var isLoading = false
    @State private var navPath  = NavigationPath()

    /// Shared player — lives here so audio outlives any individual child view.
    @State private var audioPlayer = BibleAudioPlayer()

    private var profile: UserProfile? { profiles.first }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationStack(path: $navPath) {
                BibleBookListView(
                    books: books,
                    language: selectedLanguage,
                    isLoading: isLoading
                )
                .navigationTitle("Holy Bible")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        languageMenu
                    }
                }
                .background(DesignSystem.warmCream)
                // Centralised destinations — registered at stack root so
                // they are always active, even when pushed programmatically.
                .navigationDestination(for: BibleBook.self) { book in
                    BibleChapterGridView(book: book, language: selectedLanguage)
                }
                .navigationDestination(for: BibleChapterNav.self) { nav in
                    BibleReaderView(book: nav.book, chapter: nav.chapter,
                                    language: selectedLanguage,
                                    highlightVerse: nav.verse)
                }
            }
            .onChange(of: router.bibleDeepLink) { _, link in
                guard let link else { return }
                handleDeepLink(link)
            }

            // ── Persistent audio bar — visible on any screen in the Bible tab ──
            if audioPlayer.isLoading || audioPlayer.isAvailable {
                BibleAudioPlayerBar(audio: audioPlayer)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: audioPlayer.isAvailable)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: audioPlayer.isLoading)
        // Inject the player into the environment — BibleReaderView reads it from here
        .environment(audioPlayer)
        .onAppear {
            // Seed from user's parallelLanguage preference; fall back to Amharic.
            // Migrate legacy "en" (KJV) → "niv" since we now use NIV for English.
            if let lang = profile?.parallelLanguage, !lang.isEmpty {
                selectedLanguage = lang == "en" ? "niv" : lang
            }
            Task { await loadBooks() }
        }
        .onChange(of: selectedLanguage) {
            Task { await loadBooks() }
        }
    }

    // MARK: - Language menu

    private var languageMenu: some View {
        Menu {
            Button {
                selectedLanguage = "niv"
            } label: {
                Label("🇺🇸 English (NIV)", systemImage: selectedLanguage == "niv" ? "checkmark" : "")
            }

            ForEach(EthiopianBibleService.languages, id: \.code) { lang in
                Button {
                    selectedLanguage = lang.code
                } label: {
                    Label(
                        "\(lang.flagEmoji) \(lang.nativeName)",
                        systemImage: selectedLanguage == lang.code ? "checkmark" : ""
                    )
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentLanguageLabel)
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(DesignSystem.pastoralGold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(DesignSystem.pastoralGold.opacity(0.10))
            .clipShape(Capsule())
        }
    }

    private var currentLanguageLabel: String {
        if selectedLanguage == "niv" { return "English (NIV)" }
        return EthiopianBibleService.languages
            .first { $0.code == selectedLanguage }?.nativeName ?? selectedLanguage
    }

    // MARK: - Deep-link

    /// Navigates to a specific book + chapter when "Go to verse" is tapped.
    /// Switches the Bible language to NIV, loads books if needed, then pushes
    /// both a BibleBook and BibleChapterNav onto the navigation path so the
    /// reader opens directly at the right chapter.
    private func handleDeepLink(_ link: BibleDeepLink) {
        Task { @MainActor in
            // Fetch NIV books directly — avoids the selectedLanguage onChange
            // race that would start a second concurrent loadBooks() call.
            let nivBooks = await EthiopianBibleService.shared.books(language: "niv")

            guard let book = nivBooks.first(where: {
                $0.abbreviation.uppercased() == link.book.uppercased()
            }) else { return }

            // Apply the loaded books and language together in one update.
            books            = nivBooks
            selectedLanguage = "niv"

            // Reset path then push book → chapter in one operation.
            navPath = NavigationPath()
            navPath.append(book)
            navPath.append(BibleChapterNav(book: book, chapter: link.chapter, verse: link.verse))

            router.bibleDeepLink = nil
        }
    }

    // MARK: - Data

    private func loadBooks() async {
        isLoading = true
        books = await EthiopianBibleService.shared.books(language: selectedLanguage)
        isLoading = false
    }
}
