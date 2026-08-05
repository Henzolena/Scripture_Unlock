import Foundation
import Auth

@Observable
final class VerseNoteService {
    static let shared = VerseNoteService()
    private init() {}

    // In-memory cache: key = verseRef
    private(set) var notes: [String: VerseNote] = [:]

    struct VerseNote: Identifiable, Codable {
        let id: String
        let verseRef: String
        var body: String
        let createdAt: String
        var updatedAt: String

        enum CodingKeys: String, CodingKey {
            case id, body
            case verseRef  = "verse_ref"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
    }

    func note(for verseRef: String) -> VerseNote? { notes[verseRef] }
    func hasNote(for verseRef: String) -> Bool { notes[verseRef]?.body.isEmpty == false }

    func load(verseRef: String) async {
        guard let session = try? await SupabaseService.shared.currentSession() else { return }
        let encoded = verseRef.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? verseRef
        let result: [VerseNote]? = await sbGet(
            path: "verse_notes",
            query: "user_id=eq.\(session.user.id.uuidString)&verse_ref=eq.\(encoded)&limit=1",
            token: session.accessToken
        )
        if let note = result?.first {
            await MainActor.run { notes[verseRef] = note }
        }
    }

    func save(verseRef: String, book: String, chapter: Int, verse: Int, body: String) async {
        guard let session = try? await SupabaseService.shared.currentSession() else { return }
        let isoNow = ISO8601DateFormatter().string(from: Date())
        let payload: [String: Any] = [
            "user_id": session.user.id.uuidString,
            "verse_ref": verseRef, "book": book,
            "chapter": chapter, "verse": verse,
            "body": body, "updated_at": isoNow
        ]
        let result: [VerseNote]? = await sbPost(
            path: "verse_notes", body: payload,
            token: session.accessToken,
            prefer: "resolution=merge-duplicates,return=representation"
        )
        if let saved = result?.first {
            await MainActor.run { notes[verseRef] = saved }
        }
    }

    func delete(verseRef: String) async {
        guard let session = try? await SupabaseService.shared.currentSession() else { return }
        let encoded = verseRef.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? verseRef
        await sbDelete(
            path: "verse_notes",
            query: "user_id=eq.\(session.user.id.uuidString)&verse_ref=eq.\(encoded)",
            token: session.accessToken
        )
        await MainActor.run { notes[verseRef] = nil }
    }

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

    private func sbPost<T: Decodable>(path: String, body: [String: Any], token: String, prefer: String) async -> T? {
        guard let url = URL(string: "https://\(sbURL)/rest/v1/\(path)"),
              let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"; req.httpBody = httpBody
        req.setValue(sbAnon, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(prefer, forHTTPHeaderField: "Prefer")
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
