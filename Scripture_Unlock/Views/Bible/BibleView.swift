import SwiftUI
import SwiftData

/// Root of the Bible tab.
/// Owns language selection and drives navigation into the book list.
struct BibleView: View {

    // MARK: - Init

    init() {}

    // MARK: - State

    @Query private var profiles: [UserProfile]
    @State private var selectedLanguage: String = "am"
    @State private var books: [BibleBook] = []
    @State private var isLoading = false

    private var profile: UserProfile? { profiles.first }

    // MARK: - Body

    var body: some View {
        NavigationStack {
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
        }
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

    // MARK: - Data

    private func loadBooks() async {
        isLoading = true
        books = await EthiopianBibleService.shared.books(language: selectedLanguage)
        isLoading = false
    }
}
