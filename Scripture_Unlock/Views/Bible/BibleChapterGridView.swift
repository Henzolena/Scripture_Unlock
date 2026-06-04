import SwiftUI

/// Grid of chapter-number buttons for a given Bible book.
struct BibleChapterGridView: View {

    let book:     BibleBook
    let language: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Book info header
                bookHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // Chapter grid — value-based NavigationLink so DragGesture
                // conflicts can't steal the tap
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(1...book.chapterCount, id: \.self) { chapter in
                        NavigationLink(value: BibleChapterNav(book: book, chapter: chapter)) {
                            ChapterCell(number: chapter)
                        }
                        .buttonStyle(ChapterCellButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        // Note: BibleChapterNav destination is registered in BibleView (stack root)
        .background(DesignSystem.warmCream)
        .navigationTitle(book.name)
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Book header

    private var bookHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            if book.name != book.englishName {
                Text(book.englishName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DesignSystem.slate400)
            }

            HStack(spacing: 12) {
                Label(book.testament == "OT" ? "Old Testament" : "New Testament",
                      systemImage: "book.closed.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.pastoralGold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DesignSystem.pastoralGold.opacity(0.10))
                    .clipShape(Capsule())

                Text("\(book.chapterCount) chapters")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.slate400)
            }
        }
    }
}

// MARK: - Chapter cell

private struct ChapterCell: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(DesignSystem.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(DesignSystem.surface)
            .cornerRadius(12)
            .shadow(color: DesignSystem.shadow1, radius: 4, x: 0, y: 2)
    }
}

// MARK: - Press animation ButtonStyle
// Keeps the scale-down animation without blocking the NavigationLink tap

private struct ChapterCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
