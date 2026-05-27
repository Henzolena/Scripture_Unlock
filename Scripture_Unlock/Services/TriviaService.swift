import Foundation

/// Manages the question bank and enforces the anti-cheese rule:
/// a missed question is never repeated — a different question
/// from a different book is always substituted.
@Observable
final class TriviaService {

    static let shared = TriviaService()

    /// All available questions (loaded from bundle + optionally API.Bible).
    private(set) var allQuestions: [TriviaQuestion] = TriviaQuestion.samples

    /// Questions shown in the current morning session (reset each day).
    private var sessionUsedIds: Set<String> = []

    private init() {}

    // MARK: - Question selection

    func question(
        forStep step: Int,
        packId: String,
        difficulty: Difficulty,
        excluding: Set<String> = []
    ) -> TriviaQuestion? {
        let pool = allQuestions.filter {
            $0.packId == packId &&
            $0.difficulty == difficulty &&
            !excluding.contains($0.id) &&
            !sessionUsedIds.contains($0.id)
        }
        return pool.randomElement()
            ?? allQuestions.filter { $0.packId == packId && !excluding.contains($0.id) }.randomElement()
            ?? allQuestions.filter { !excluding.contains($0.id) }.randomElement()
    }

    /// Anti-cheese: pick a replacement after a wrong answer.
    /// MUST be from a different book than the missed question.
    func replacementQuestion(
        after missed: TriviaQuestion,
        packId: String,
        difficulty: Difficulty,
        excluding: Set<String>
    ) -> TriviaQuestion? {
        var excl = excluding
        excl.insert(missed.id)

        let differentBook = allQuestions.filter {
            $0.packId == packId &&
            $0.book != missed.book &&
            !excl.contains($0.id)
        }
        if let q = differentBook.randomElement() { return q }

        let anyPackDiffBook = allQuestions.filter {
            $0.book != missed.book &&
            !excl.contains($0.id)
        }
        if let q = anyPackDiffBook.randomElement() { return q }

        return allQuestions.filter { !excl.contains($0.id) }.randomElement()
    }

    // MARK: - Session management

    func markSeen(_ question: TriviaQuestion) {
        sessionUsedIds.insert(question.id)
    }

    func resetSession() {
        sessionUsedIds = []
    }

    // MARK: - Remote fetch (API.Bible)

    func fetchFromAPI(translation: Translation, packId: String) async {
        guard let apiKey = Bundle.main.infoDictionary?["BIBLE_API_KEY"] as? String,
              !apiKey.isEmpty else { return }

        let bibleIdMap: [Translation: String] = [
            .esv: "06125adad2d5898a-01",
            .niv: "78a9f6124f344018-01",
            .kjv: "de4e12af7f28f599-02",
        ]
        guard let bibleId = bibleIdMap[translation] else { return }
        let urlString = "https://api.scripture.api.bible/v1/bibles/\(bibleId)/books"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "api-key")

        do {
            let (_, _) = try await URLSession.shared.data(for: request)
            // TODO: Parse response and hydrate allQuestions
        } catch {
            print("[TriviaService] API.Bible fetch failed: \(error)")
        }
    }
}
