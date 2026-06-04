import Foundation

/// A single trivia question fetched from API.Bible or the local bundle.
struct TriviaQuestion: Identifiable, Codable, Hashable {

    let id: String           // e.g. "GEN.6.14-mcq"
    let kind: Kind
    let book: String         // e.g. "Genesis"
    let packId: String       // which VersePack this belongs to
    let difficulty: Difficulty

    // MCQ fields
    let prompt: String?
    let options: [String]
    let answerIndex: Int

    // Fill fields
    let fillPre: String?     // text before the blank
    let fillPost: String?    // text after the blank

    let verseRef: String     // e.g. "Genesis 6:14"
    let verseText: String    // Full verse for the reveal card

    enum Kind: String, Codable { case mcq, fill }

    // MARK: - Memberwise init (required once a custom Decodable init is added)

    init(id: String, kind: Kind, book: String, packId: String, difficulty: Difficulty,
         prompt: String?, options: [String], answerIndex: Int,
         fillPre: String?, fillPost: String?,
         verseRef: String, verseText: String) {
        self.id          = id
        self.kind        = kind
        self.book        = book
        self.packId      = packId
        self.difficulty  = difficulty
        self.prompt      = prompt
        self.options     = options
        self.answerIndex = answerIndex
        self.fillPre     = fillPre
        self.fillPost    = fillPost
        self.verseRef    = verseRef
        self.verseText   = verseText
    }

    // MARK: - Custom decoder (handles null options/answerIndex from Gemini)

    enum CodingKeys: String, CodingKey {
        case id, kind, book, packId, difficulty
        case prompt, options, answerIndex
        case fillPre, fillPost
        case verseRef, verseText
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(String.self,     forKey: .id)
        kind        = try c.decode(Kind.self,        forKey: .kind)
        book        = try c.decode(String.self,     forKey: .book)
        packId      = try c.decode(String.self,     forKey: .packId)
        difficulty  = try c.decode(Difficulty.self, forKey: .difficulty)
        prompt      = try c.decodeIfPresent(String.self, forKey: .prompt)
        // Gemini sometimes returns null for these on fill questions — default safely
        options     = (try? c.decode([String].self, forKey: .options)) ?? []
        answerIndex = (try? c.decode(Int.self,      forKey: .answerIndex)) ?? 0
        fillPre     = try c.decodeIfPresent(String.self, forKey: .fillPre)
        fillPost    = try c.decodeIfPresent(String.self, forKey: .fillPost)
        verseRef    = try c.decode(String.self,     forKey: .verseRef)
        verseText   = try c.decode(String.self,     forKey: .verseText)
    }

    /// Safe accessor — never crashes even if Gemini returned a bad answerIndex.
    var correctAnswer: String {
        guard !options.isEmpty else { return "" }
        let safeIndex = max(0, min(answerIndex, options.count - 1))
        return options[safeIndex]
    }

    /// Human-readable label shown in the question header.
    var displayPrompt: String {
        switch kind {
        case .mcq:  return prompt ?? ""
        case .fill: return "\(fillPre ?? "") ___ \(fillPost ?? "")"
        }
    }
}
