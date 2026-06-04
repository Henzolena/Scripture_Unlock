import SwiftUI

/// Shared navigation state injected at the root level so any view can
/// switch tabs or deep-link into the Bible reader programmatically.
@Observable
final class NavigationRouter {

    // MARK: - Tab selection
    var selectedTab: MainTabView.Tab = .home

    // MARK: - Bible deep-link
    /// Set this to trigger programmatic navigation inside BibleView.
    var bibleDeepLink: BibleDeepLink? = nil
}

/// Destination for a "Go to verse" deep-link.
struct BibleDeepLink {
    let book:     String   // abbreviation e.g. "EPH"
    let bookName: String   // display name e.g. "Ephesians"
    let chapter:  Int
    let verse:    Int
}

/// Navigation value pushed onto the BibleView NavigationStack when a chapter
/// is selected. Carries both the book and chapter so destinations can be
/// registered centrally at the stack root without Int collisions.
struct BibleChapterNav: Hashable {
    let book:    BibleBook
    let chapter: Int
}
