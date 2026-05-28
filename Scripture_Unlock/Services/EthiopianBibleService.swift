import Foundation

// MARK: - EthiopianBibleService
//
// Fetches Bible verses from the Ethiopian Bible API (your own Railway deployment).
//
// Base URL : https://ethiopian-bible-api-production.up.railway.app
// Docs     : /docs
// Auth     : None required
//
// Supported languages
//   "am" → Amharic   (አማርኛ)
//   "or" → Oromo     (Afaan Oromoo)
//   "ti" → Tigrigna  (ትግርኛ)
//   "en" → English KJV
//
// Verse endpoint: GET /api/v1/{lang}/books/{bookNumber}/{chapter}/{verse}
// Response      : { book, book_name, chapter, verse, text, language }

final class EthiopianBibleService {

    static let shared = EthiopianBibleService()
    private init() {}

    // MARK: - Config

    private let baseURL = "https://ethiopian-bible-api-production.up.railway.app/api/v1"
    private let session = URLSession.shared

    // MARK: - Cache  (key = "bookNum-chapter-verse-lang")

    private var cache: [String: EthiopianVerse] = [:]

    // MARK: - Language metadata

    struct LanguageInfo {
        let code:       String
        let nativeName: String
        let flagEmoji:  String
    }

    static let languages: [LanguageInfo] = [
        LanguageInfo(code: "am", nativeName: "አማርኛ",        flagEmoji: "🇪🇹"),
        LanguageInfo(code: "or", nativeName: "Afaan Oromoo", flagEmoji: "🇪🇹"),
        LanguageInfo(code: "ti", nativeName: "ትግርኛ",        flagEmoji: "🇪🇹"),
    ]

    static func info(for code: String) -> LanguageInfo? {
        languages.first { $0.code == code }
    }

    // MARK: - Public API

    /// Fetch a single verse in the requested language.
    /// Returns nil if the language code is empty or the request fails.
    func verse(book bookNum: Int, chapter: Int, verse: Int, language: String) async -> EthiopianVerse? {
        guard !language.isEmpty else { return nil }

        let key = "\(bookNum)-\(chapter)-\(verse)-\(language)"
        if let cached = cache[key] { return cached }

        let urlString = "\(baseURL)/\(language)/books/\(bookNum)/\(chapter)/\(verse)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(EthiopianVerse.self, from: data)
            cache[key] = decoded
            return decoded
        } catch {
            return nil
        }
    }

    /// Convenience: parse an English verse reference ("John 3:16") and fetch in the given language.
    func verse(ref: String, language: String) async -> String? {
        guard !language.isEmpty else { return nil }
        guard let (bookNum, ch, vs) = parseRef(ref) else { return nil }
        return await verse(book: bookNum, chapter: ch, verse: vs, language: language)?.text
    }

    // MARK: - Book number lookup (OT + NT canonical order)

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
        let lower = ref.lowercased()
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)

        let pattern = #"^([\w\s]+?)\s+(\d+)[:\.፡](\d+)$"#
        guard let regex  = try? NSRegularExpression(pattern: pattern),
              let match  = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let bRange = Range(match.range(at: 1), in: lower),
              let cRange = Range(match.range(at: 2), in: lower),
              let vRange = Range(match.range(at: 3), in: lower)
        else { return nil }

        let bookKey = String(lower[bRange]).replacingOccurrences(of: " ", with: "")
        guard let bookNum = Self.bookNumbers[bookKey],
              let ch      = Int(lower[cRange]),
              let vs      = Int(lower[vRange])
        else { return nil }

        return (bookNum, ch, vs)
    }
}

// MARK: - Response model

struct EthiopianVerse: Decodable {
    let book:      String   // abbreviation e.g. "JHN"
    let bookName:  String   // localized name e.g. "ዮሐንስ"
    let chapter:   Int
    let verse:     Int
    let text:      String
    let language:  String

    enum CodingKeys: String, CodingKey {
        case book
        case bookName = "book_name"
        case chapter
        case verse
        case text
        case language
    }
}
