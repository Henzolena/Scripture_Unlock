import SwiftUI

/// Shows all 66 Bible books grouped into Old Testament / New Testament sections,
/// with a live search bar for quick navigation.
struct BibleBookListView: View {

    let books:     [BibleBook]
    let language:  String
    let isLoading: Bool

    @State private var searchText    = ""
    @State private var audioIndex:   [String: Bool] = [:]

    private var oldTestament: [BibleBook] {
        filtered(books.filter { $0.testament == "OT" })
    }
    private var newTestament: [BibleBook] {
        filtered(books.filter { $0.testament == "NT" })
    }

    private func filtered(_ list: [BibleBook]) -> [BibleBook] {
        guard !searchText.isEmpty else { return list }
        let q = searchText.lowercased()
        return list.filter {
            $0.name.lowercased().contains(q) ||
            $0.englishName.lowercased().contains(q) ||
            $0.abbreviation.lowercased().contains(q)
        }
    }

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
        .background(DesignSystem.warmCream)
        .task(id: language) {
            if let cov = await EthiopianBibleService.shared.coverage(language: language) {
                audioIndex = cov.bookIndex.mapValues { $0.audio }
            }
        }
    }

    // MARK: - Book list

    private var bookList: some View {
        ScrollView {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DesignSystem.slate400)
                    .font(.system(size: 14))
                TextField("Search books…", text: $searchText)
                    .font(.system(size: 14))
                    .foregroundStyle(DesignSystem.ink)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DesignSystem.slate400)
                            .font(.system(size: 14))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(DesignSystem.surface)
            .cornerRadius(12)
            .shadow(color: DesignSystem.shadow1, radius: 4, x: 0, y: 1)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)

            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {

                if !oldTestament.isEmpty {
                    Section {
                        ForEach(oldTestament) { book in
                            NavigationLink(value: book) {
                                BookRow(book: book, hasAudio: audioIndex[book.abbreviation] ?? false)
                            }
                            .buttonStyle(BookRowButtonStyle())
                            .padding(.horizontal, 20)
                        }
                    } header: {
                        sectionHeader("Old Testament", count: books.filter { $0.testament == "OT" }.count)
                    }
                }

                if !newTestament.isEmpty {
                    Section {
                        ForEach(newTestament) { book in
                            NavigationLink(value: book) {
                                BookRow(book: book, hasAudio: audioIndex[book.abbreviation] ?? false)
                            }
                            .buttonStyle(BookRowButtonStyle())
                            .padding(.horizontal, 20)
                        }
                    } header: {
                        sectionHeader("New Testament", count: books.filter { $0.testament == "NT" }.count)
                    }
                }

                if oldTestament.isEmpty && newTestament.isEmpty && !searchText.isEmpty {
                    noResultsView
                }
            }
            .padding(.bottom, 32)
        }
        .background(DesignSystem.warmCream)
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            GoldRule(width: 18)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(DesignSystem.slate600)
            Spacer()
            Text("\(count) books")
                .font(.system(size: 11))
                .foregroundStyle(DesignSystem.slate400)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(DesignSystem.warmCream)
    }

    // MARK: - Loading / empty / no-results states

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

    private var noResultsView: some View {
        VStack(spacing: 10) {
            Image(systemName: "book.closed")
                .font(.system(size: 32))
                .foregroundStyle(DesignSystem.slate400)
            Text("No books match \"\(searchText)\"")
                .font(.system(size: 14))
                .foregroundStyle(DesignSystem.slate400)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Book row

private struct BookRow: View {
    let book:     BibleBook
    let hasAudio: Bool

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
                    .font(.system(size: 15, weight: .semibold))
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

            // Audio indicator
            if hasAudio {
                Image(systemName: "headphones")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.pastoralGold.opacity(0.65))
            }

            // Chapter count chip
            HStack(spacing: 2) {
                Text("\(book.chapterCount)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DesignSystem.pastoralGold)
                Text("ch")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.slate400)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignSystem.slate400.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DesignSystem.surface)
        .cornerRadius(14)
        .shadow(color: DesignSystem.shadow1, radius: 4, x: 0, y: 1)
        .padding(.vertical, 4)
    }
}

// MARK: - Press animation

private struct BookRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
