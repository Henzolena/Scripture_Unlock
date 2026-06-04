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

    // MARK: - Public

    func today() async -> VerseOfDay? {
        guard let url = URL(string: baseURL) else { return nil }

        // Always fetch fresh — never serve a cached response
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let dto = try JSONDecoder().decode(VotdResponse.self, from: data)
            guard let verse = dto.verse, !verse.text.isEmpty else { return nil }

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
        } catch { return nil }
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
