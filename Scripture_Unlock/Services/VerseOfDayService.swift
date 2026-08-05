import Foundation

// MARK: - Model

struct VerseOfDay {
    let ref:         String   // "Ephesians 2:8"
    let text:        String
    let translation: String   // "NIV"
    let book:        String   // "EPH"
    let chapter:     Int
    let verse:       Int
    let audioURL:    String?  // nil until Railway generates the audio
    /// "pending" | "generating" | "ready" | "failed" | nil (no row yet)
    let audioStatus: String?
}

// MARK: - Service

/// Fetches today's VOTD from the single Railway endpoint GET /api/v1/votd/today.
/// That endpoint returns the curated verse text AND the audio metadata together —
/// eliminating the mismatch that occurred when verse text came from /niv/votd
/// and audio came from Supabase separately.
final class VerseOfDayService {

    static let shared = VerseOfDayService()
    private init() {}

    private let baseURL = "https://ethiopian-bible-api-production.up.railway.app/api/v1/votd/today"

    private var sbURL:  String { Bundle.main.object(forInfoDictionaryKey: "SUPABASE_HOST")     as? String ?? "" }
    private var sbAnon: String { Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? "" }

    // MARK: - Public

    func today() async -> VerseOfDay? {
        guard let url = URL(string: baseURL) else { return await fallbackToSupabase() }

        // Always fetch fresh — never serve a cached response
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return await fallbackToSupabase()
            }
            let dto = try JSONDecoder().decode(VotdResponse.self, from: data)
            guard let verse = dto.verse, !verse.text.isEmpty else {
                return await fallbackToSupabase()
            }

            let ref = "\(verse.bookName) \(verse.chapter):\(verse.verse)"
            let audioStatus = dto.audioStatus
            let audioURL    = (audioStatus == "ready") ? dto.audioUrl : nil

            return VerseOfDay(
                ref:         ref,
                text:        verse.text,
                translation: "NIV",
                book:        verse.book,
                chapter:     verse.chapter,
                verse:       verse.verse,
                audioURL:    audioURL,
                audioStatus: audioStatus
            )
        } catch { return await fallbackToSupabase() }
    }

    // MARK: - Supabase fallback

    private func fallbackToSupabase() async -> VerseOfDay? {
        guard let url = URL(string: "https://\(sbURL)/rest/v1/verse_of_the_day?select=*&order=date.desc&limit=1") else { return nil }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        req.setValue(sbAnon, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let rows = try? JSONDecoder().decode([SupabaseVotdRow].self, from: data),
              let row = rows.first,
              let text = row.verseText, !text.isEmpty,
              let book = row.book,
              let chapter = row.chapter,
              let verse = row.verse else { return nil }
        let bookName = row.bookName ?? book
        let ref = row.verseRef ?? "\(bookName) \(chapter):\(verse)"
        return VerseOfDay(
            ref:         ref,
            text:        text,
            translation: row.translation ?? "NIV",
            book:        book,
            chapter:     chapter,
            verse:       verse,
            audioURL:    row.audioStatus == "ready" ? row.audioUrl : nil,
            audioStatus: row.audioStatus
        )
    }

    // MARK: - DTOs

    private struct VotdResponse: Decodable {
        let verse:       VerseDTO?
        let audioUrl:    String?
        let audioStatus: String?
        let date:        String?

        enum CodingKeys: String, CodingKey {
            case verse
            case audioUrl    = "audio_url"
            case audioStatus = "audio_status"
            case date
        }
    }

    private struct SupabaseVotdRow: Decodable {
        let verseRef:    String?
        let verseText:   String?
        let translation: String?
        let book:        String?
        let bookName:    String?
        let chapter:     Int?
        let verse:       Int?
        let audioUrl:    String?
        let audioStatus: String?

        enum CodingKeys: String, CodingKey {
            case translation, book, chapter, verse
            case verseRef    = "verse_ref"
            case verseText   = "verse_text"
            case bookName    = "book_name"
            case audioUrl    = "audio_url"
            case audioStatus = "audio_status"
        }
    }

    private struct VerseDTO: Decodable {
        let book:     String
        let bookName: String
        let chapter:  Int
        let verse:    Int
        let text:     String

        enum CodingKeys: String, CodingKey {
            case book, chapter, verse, text
            case bookName = "book_name"
        }
    }
}
