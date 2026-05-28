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

    /// True when this question came from Gemini (not the bundled static samples).
    var isAIGenerated: Bool {
        !TriviaQuestion.samples.contains(where: { $0.id == id })
    }

    /// Human-readable label shown in the question header.
    var displayPrompt: String {
        switch kind {
        case .mcq:  return prompt ?? ""
        case .fill: return "\(fillPre ?? "") ___ \(fillPost ?? "")"
        }
    }
}

// MARK: - Bundled sample questions (used offline / first launch)

extension TriviaQuestion {
    static let samples: [TriviaQuestion] = [
        TriviaQuestion(
            id: "GEN.6.14-mcq", kind: .mcq, book: "Genesis",
            packId: "ot", difficulty: .regular,
            prompt: "Who was commanded to build the ark before the flood?",
            options: ["Abraham", "Noah", "Moses", "Enoch"],
            answerIndex: 1, fillPre: nil, fillPost: nil,
            verseRef: "Genesis 6:14",
            verseText: "Make yourself an ark of gopher wood. Make rooms in the ark, and cover it inside and out with pitch."
        ),
        TriviaQuestion(
            id: "PSA.23.1-fill", kind: .fill, book: "Psalms",
            packId: "psalms", difficulty: .gentle,
            prompt: nil,
            options: ["rock", "light", "shepherd", "refuge"],
            answerIndex: 2, fillPre: "The Lord is my", fillPost: "; I shall not want.",
            verseRef: "Psalm 23:1",
            verseText: "The Lord is my shepherd; I shall not want."
        ),
        TriviaQuestion(
            id: "LUK.2.4-mcq", kind: .mcq, book: "Luke",
            packId: "gospels", difficulty: .gentle,
            prompt: "In which town was Jesus born?",
            options: ["Nazareth", "Jerusalem", "Bethlehem", "Capernaum"],
            answerIndex: 2, fillPre: nil, fillPost: nil,
            verseRef: "Luke 2:4–7",
            verseText: "And Joseph also went up from Galilee... to the city of David, which is called Bethlehem."
        ),
        TriviaQuestion(
            id: "EXO.14.21-mcq", kind: .mcq, book: "Exodus",
            packId: "ot", difficulty: .regular,
            prompt: "Through which sea did Moses lead Israel out of Egypt?",
            options: ["Sea of Galilee", "Dead Sea", "Red Sea", "Jordan River"],
            answerIndex: 2, fillPre: nil, fillPost: nil,
            verseRef: "Exodus 14:21",
            verseText: "Then Moses stretched out his hand over the sea, and the Lord drove the sea back by a strong east wind."
        ),
        TriviaQuestion(
            id: "PSA.27.1-fill", kind: .fill, book: "Psalms",
            packId: "psalms", difficulty: .gentle,
            prompt: nil,
            options: ["shepherd", "light", "tower", "banner"],
            answerIndex: 1, fillPre: "The Lord is my", fillPost: "and my salvation; whom shall I fear?",
            verseRef: "Psalm 27:1",
            verseText: "The Lord is my light and my salvation; whom shall I fear? The Lord is the stronghold of my life."
        ),
        TriviaQuestion(
            id: "MAT.3.13-mcq", kind: .mcq, book: "Matthew",
            packId: "gospels", difficulty: .regular,
            prompt: "Who baptized Jesus in the Jordan?",
            options: ["Andrew", "John the Baptist", "Peter", "Philip"],
            answerIndex: 1, fillPre: nil, fillPost: nil,
            verseRef: "Matthew 3:13",
            verseText: "Then Jesus came from Galilee to the Jordan to John, to be baptized by him."
        ),
        TriviaQuestion(
            id: "PHP.4.13-fill", kind: .fill, book: "Philippians",
            packId: "epistles", difficulty: .gentle,
            prompt: nil,
            options: ["God", "faith", "hope", "him"],
            answerIndex: 3, fillPre: "I can do all things through", fillPost: "who strengthens me.",
            verseRef: "Philippians 4:13",
            verseText: "I can do all things through him who strengthens me."
        ),
        TriviaQuestion(
            id: "PRO.6.6-fill", kind: .fill, book: "Proverbs",
            packId: "proverbs", difficulty: .regular,
            prompt: nil,
            options: ["humble", "wise", "strong", "patient"],
            answerIndex: 1, fillPre: "Go to the ant, O sluggard; consider her ways, and be", fillPost: ".",
            verseRef: "Proverbs 6:6",
            verseText: "Go to the ant, O sluggard; consider her ways, and be wise."
        ),
        TriviaQuestion(
            id: "ISA.40.31-fill", kind: .fill, book: "Isaiah",
            packId: "ot", difficulty: .regular,
            prompt: nil,
            options: ["walk", "wait", "trust", "seek"],
            answerIndex: 1, fillPre: "But they who", fillPost: "for the Lord shall renew their strength.",
            verseRef: "Isaiah 40:31",
            verseText: "But they who wait for the Lord shall renew their strength; they shall mount up with wings like eagles."
        ),
        TriviaQuestion(
            id: "JHN.3.16-fill", kind: .fill, book: "John",
            packId: "gospels", difficulty: .gentle,
            prompt: nil,
            options: ["sent", "saved", "loved", "gave"],
            answerIndex: 2, fillPre: "For God so", fillPost: "the world that he gave his only Son.",
            verseRef: "John 3:16",
            verseText: "For God so loved the world, that he gave his only Son, that whoever believes in him should not perish but have eternal life."
        ),
    ]
}
