import Foundation

// MARK: - BetezionService
//
// Fetches Amharic Bible text from api.betezion.com.
//
// To activate:
//   1. Register at https://www.betezion.com and obtain an API key.
//   2. Add to Secrets.xcconfig:
//        BETEZION_API_KEY  = your-key-here
//        BETEZION_USERNAME = your-username-here   (if required by your plan)
//   3. Toggle "Amharic alongside English" in Settings.
//
// Confirmed via probing (May 2026):
//   Base URL : https://api.betezion.com
//   Auth     : api_key query param (+ optional username param)
//   Envelope : { "status": Int, "status_message": String, "data": {...} }
//   Endpoints: /verse, /chapter, /books

final class BetezionService {

    static let shared = BetezionService()
    private init() {}

    // MARK: - Config  (injected from Secrets.xcconfig via Info.plist)

    private var apiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "BETEZION_API_KEY") as? String ?? ""
    }
    private var username: String {
        Bundle.main.object(forInfoDictionaryKey: "BETEZION_USERNAME") as? String ?? ""
    }

    private let baseURL = "https://api.betezion.com"
    private let session = URLSession.shared

    // MARK: - Cache

    private var cache: [String: BetezionVerse] = [:]

    // MARK: - Public API

    /// Fetch a single Amharic verse. Returns nil if the key is missing or request fails.
    func verse(book: Int, chapter: Int, verse: Int) async -> BetezionVerse? {
        guard !apiKey.isEmpty else { return nil }

        let key = "\(book)-\(chapter)-\(verse)"
        if let cached = cache[key] { return cached }

        var components    = URLComponents(string: "\(baseURL)/verse")!
        var queryItems    = [
            URLQueryItem(name: "book",    value: "\(book)"),
            URLQueryItem(name: "chapter", value: "\(chapter)"),
            URLQueryItem(name: "verse",   value: "\(verse)"),
            URLQueryItem(name: "api_key", value: apiKey),
        ]
        if !username.isEmpty {
            queryItems.append(URLQueryItem(name: "username", value: username))
        }
        components.queryItems = queryItems

        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let envelope = try JSONDecoder().decode(BetezionEnvelope<BetezionVerseData>.self, from: data)
            guard envelope.status == 200, let verseData = envelope.data else { return nil }
            let result = BetezionVerse(
                amharicText: verseData.amharicText ?? verseData.text ?? "",
                reference:   "\(verseData.bookNameAmharic ?? "") \(chapter):\(verse)"
            )
            cache[key] = result
            return result
        } catch {
            return nil
        }
    }

    /// Fetch all verses in a chapter (used for chapter display).
    func chapter(book: Int, chapter: Int) async -> [BetezionVerse] {
        guard !apiKey.isEmpty else { return [] }

        var components = URLComponents(string: "\(baseURL)/chapter")!
        var queryItems = [
            URLQueryItem(name: "book",    value: "\(book)"),
            URLQueryItem(name: "chapter", value: "\(chapter)"),
            URLQueryItem(name: "api_key", value: apiKey),
        ]
        if !username.isEmpty {
            queryItems.append(URLQueryItem(name: "username", value: username))
        }
        components.queryItems = queryItems
        guard let url = components.url else { return [] }

        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            let envelope = try JSONDecoder().decode(BetezionEnvelope<[BetezionVerseData]>.self, from: data)
            guard envelope.status == 200, let verses = envelope.data else { return [] }
            return verses.enumerated().map { idx, v in
                BetezionVerse(
                    amharicText: v.amharicText ?? v.text ?? "",
                    reference:   "\(v.bookNameAmharic ?? "") \(chapter):\(idx + 1)"
                )
            }
        } catch {
            return []
        }
    }

    /// Resolve an English verse reference (e.g. "John 3:16") to a
    /// BetezionVerse using the books list for book-number lookup.
    func amharic(forRef ref: String) async -> String? {
        guard !apiKey.isEmpty else { return nil }
        guard let (bookNum, ch, vs) = parseRef(ref) else { return nil }
        return await verse(book: bookNum, chapter: ch, verse: vs)?.amharicText
    }

    // MARK: - Book number lookup table (OT + NT canonical order)

    private static let bookNumbers: [String: Int] = {
        let names = [
            "genesis":1,"exodus":2,"leviticus":3,"numbers":4,"deuteronomy":5,
            "joshua":6,"judges":7,"ruth":8,"1samuel":9,"2samuel":10,
            "1kings":11,"2kings":12,"1chronicles":13,"2chronicles":14,
            "ezra":15,"nehemiah":16,"esther":17,"job":18,"psalms":19,"psalm":19,
            "proverbs":20,"ecclesiastes":21,"song":22,"isaiah":23,"jeremiah":24,
            "lamentations":25,"ezekiel":26,"daniel":27,"hosea":28,"joel":29,
            "amos":30,"obadiah":31,"jonah":32,"micah":33,"nahum":34,
            "habakkuk":35,"zephaniah":36,"haggai":37,"zechariah":38,"malachi":39,
            "matthew":40,"mark":41,"luke":42,"john":43,"acts":44,
            "romans":45,"1corinthians":46,"2corinthians":47,"galatians":48,
            "ephesians":49,"philippians":50,"colossians":51,"1thessalonians":52,
            "2thessalonians":53,"1timothy":54,"2timothy":55,"titus":56,
            "philemon":57,"hebrews":58,"james":59,"1peter":60,"2peter":61,
            "1john":62,"2john":63,"3john":64,"jude":65,"revelation":66
        ]
        return names
    }()

    private func parseRef(_ ref: String) -> (book: Int, chapter: Int, verse: Int)? {
        // Normalise "John 3:16" → ("john", 3, 16)
        let lower = ref.lowercased()
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)

        // Split on last space before digits to separate book name from chapter:verse
        let pattern = #"^([\w\s]+?)\s+(\d+)[:\.፡](\d+)$"#
        guard let regex  = try? NSRegularExpression(pattern: pattern),
              let match  = regex.firstMatch(in: lower,
                                            range: NSRange(lower.startIndex..., in: lower)),
              let bRange = Range(match.range(at: 1), in: lower),
              let cRange = Range(match.range(at: 2), in: lower),
              let vRange = Range(match.range(at: 3), in: lower)
        else { return nil }

        let bookKey = String(lower[bRange])
            .replacingOccurrences(of: " ", with: "")
        guard let bookNum = Self.bookNumbers[bookKey],
              let ch      = Int(lower[cRange]),
              let vs      = Int(lower[vRange])
        else { return nil }

        return (bookNum, ch, vs)
    }
}

// MARK: - Response models

struct BetezionEnvelope<T: Decodable>: Decodable {
    let status: Int
    let statusMessage: String?
    let data: T?

    enum CodingKeys: String, CodingKey {
        case status
        case statusMessage = "status_message"
        case data
    }
}

struct BetezionVerseData: Decodable {
    /// Primary Amharic text field (exact key TBD once auth is confirmed)
    let amharicText:     String?
    /// Fallback key names encountered in similar APIs
    let text:            String?
    let verse:           String?
    let bookNameAmharic: String?

    enum CodingKeys: String, CodingKey {
        case amharicText     = "amharic_text"
        case text
        case verse
        case bookNameAmharic = "book_name_amharic"
    }
}

/// Clean value type returned by BetezionService callers.
struct BetezionVerse {
    let amharicText: String
    let reference:   String
}
