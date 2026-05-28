import SwiftUI

/// Shows all 66 Bible books grouped into Old Testament / New Testament sections.
struct BibleBookListView: View {

    let books:     [BibleBook]
    let language:  String
    let isLoading: Bool

    private var oldTestament: [BibleBook] { books.filter { $0.testament == "OT" } }
    private var newTestament: [BibleBook] { books.filter { $0.testament == "NT" } }

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if books.isEmpty {
                emptyView
            } else {
                bookList
            }
        }
        // Destination registered here — picked up by the parent NavigationStack in BibleView
        .navigationDestination(for: BibleBook.self) { book in
            BibleChapterGridView(book: book, language: language)
        }
        .background(DesignSystem.warmCream)
    }

    // MARK: - Book list

    private var bookList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {

                // Old Testament
                if !oldTestament.isEmpty {
                    Section {
                        ForEach(oldTestament) { book in
                            // Value-based link — no gesture conflicts, reliable in ScrollView
                            NavigationLink(value: book) {
                                BookRow(book: book)
                            }
                            .buttonStyle(BookRowButtonStyle())
                            .padding(.horizontal, 20)
                        }
                    } header: {
                        sectionHeader("Old Testament")
                    }
                }

                // New Testament
                if !newTestament.isEmpty {
                    Section {
                        ForEach(newTestament) { book in
                            NavigationLink(value: book) {
                                BookRow(book: book)
                            }
                            .buttonStyle(BookRowButtonStyle())
                            .padding(.horizontal, 20)
                        }
                    } header: {
                        sectionHeader("New Testament")
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .background(DesignSystem.warmCream)
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 8) {
            GoldRule(width: 18)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(DesignSystem.slate600)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(DesignSystem.warmCream)
    }

    // MARK: - Loading / empty states

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(DesignSystem.pastoralGold)
            Text("Loading books…")
                .font(.system(size: 14))
                .foregroundStyle(DesignSystem.slate400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 36))
                .foregroundStyle(DesignSystem.slate400)
            Text("Could not load books")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DesignSystem.ink)
            Text("Check your connection and try again.")
                .font(.system(size: 13))
                .foregroundStyle(DesignSystem.slate400)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Book row

private struct BookRow: View {
    let book: BibleBook

    var body: some View {
        HStack(spacing: 14) {
            // Book number badge
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(DesignSystem.pastoralGold.opacity(0.12))
                    .frame(width: 36, height: 36)
                Text("\(book.number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DesignSystem.pastoralGold)
            }

            // Book names
            VStack(alignment: .leading, spacing: 3) {
                Text(book.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DesignSystem.ink)
                    .lineLimit(1)
                if book.name != book.englishName {
                    Text(book.englishName)
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.slate400)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Chapter count
            HStack(spacing: 3) {
                Text("\(book.chapterCount)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DesignSystem.pastoralGold)
                Text("ch")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.slate400)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignSystem.slate400)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DesignSystem.surface)
        .cornerRadius(14)
        .shadow(color: DesignSystem.shadow1, radius: 4, x: 0, y: 2)
        .padding(.vertical, 4)
    }
}

// MARK: - Press animation ButtonStyle for book rows

private struct BookRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
