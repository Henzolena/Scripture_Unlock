import Foundation
import Auth

@Observable
final class BookmarkService {
    static let shared = BookmarkService()
    private init() {}

    private(set) var bookmarks: [Bookmark] = []
    private(set) var isLoading = false

    struct Bookmark: Identifiable, Codable {
        let id: String
        let book: String
        let chapter: Int
        let verse: Int
        let verseRef: String
        let verseText: String
        let translation: String
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id, book, chapter, verse, translation
            case verseRef  = "verse_ref"
            case verseText = "verse_text"
            case createdAt = "created_at"
        }
    }

    func isBookmarked(_ verseRef: String) -> Bool {
        bookmarks.contains { $0.verseRef == verseRef }
    }

    func load() async {
        guard let session = try? await SupabaseService.shared.currentSession() else { return }
        await MainActor.run { isLoading = true }
        let result: [Bookmark]? = await sbGet(
            path: "bookmarks",
            query: "user_id=eq.\(session.user.id.uuidString)&order=created_at.desc",
            token: session.accessToken
        )
        await MainActor.run {
            bookmarks = result ?? []
            isLoading = false
        }
    }

    func toggle(verseRef: String, book: String, chapter: Int, verse: Int,
                text: String, translation: String) async {
        if isBookmarked(verseRef) {
            await remove(verseRef: verseRef)
        } else {
            await add(verseRef: verseRef, book: book, chapter: chapter,
                      verse: verse, text: text, translation: translation)
        }
    }

    private func add(verseRef: String, book: String, chapter: Int, verse: Int,
                     text: String, translation: String) async {
        guard let session = try? await SupabaseService.shared.currentSession() else { return }
        let body: [String: Any] = [
            "user_id": session.user.id.uuidString,
            "book": book, "chapter": chapter, "verse": verse,
            "verse_ref": verseRef, "verse_text": text, "translation": translation, "note": ""
        ]
        let result: [Bookmark]? = await sbPost(
            path: "bookmarks", body: body,
            token: session.accessToken, prefer: "return=representation"
        )
        if let new = result?.first {
            await MainActor.run { bookmarks.insert(new, at: 0) }
        }
    }

    func remove(verseRef: String) async {
        guard let session = try? await SupabaseService.shared.currentSession() else { return }
        let encoded = verseRef.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? verseRef
        await sbDelete(
            path: "bookmarks",
            query: "user_id=eq.\(session.user.id.uuidString)&verse_ref=eq.\(encoded)",
            token: session.accessToken
        )
        await MainActor.run { bookmarks.removeAll { $0.verseRef == verseRef } }
    }

    var totalCount: Int { bookmarks.count }

    // MARK: - REST helpers

    private var sbURL: String { Bundle.main.object(forInfoDictionaryKey: "SUPABASE_HOST") as? String ?? "" }
    private var sbAnon: String { Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? "" }

    private func sbGet<T: Decodable>(path: String, query: String, token: String) async -> T? {
        guard let url = URL(string: "https://\(sbURL)/rest/v1/\(path)?\(query)") else { return nil }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        req.setValue(sbAnon, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func sbPost<T: Decodable>(path: String, body: [String: Any], token: String, prefer: String? = nil) async -> T? {
        guard let url = URL(string: "https://\(sbURL)/rest/v1/\(path)"),
              let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"; req.httpBody = httpBody
        req.setValue(sbAnon, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func sbDelete(path: String, query: String, token: String) async {
        guard let url = URL(string: "https://\(sbURL)/rest/v1/\(path)?\(query)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue(sbAnon, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: req)
    }
}
