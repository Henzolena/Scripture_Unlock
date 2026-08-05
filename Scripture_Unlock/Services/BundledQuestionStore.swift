import Foundation

/// Last-resort question source, loaded from the app bundle.
///
/// Why this exists
/// ───────────────
/// Every other tier needs the network: `QuestionGeneratorAgent` generates via the
/// Railway API or Gemini, and then *validates* each question by fetching the verse
/// back over the network. So with no connectivity — or with the Railway API down —
/// nothing new can enter the cache, while `consume()` permanently removes each
/// question as it is used. The cache can only drain.
///
/// When it hits zero the alarm becomes impossible to silence, which is the one
/// failure this app cannot afford. These bundled questions are the floor: they
/// need no network, are never consumed, and are always available.
///
/// They are deliberately used *last*, so a warm AI cache always wins.
final class BundledQuestionStore {

    static let shared = BundledQuestionStore()

    private let all: [TriviaQuestion]

    private init() {
        guard let url = Bundle.main.url(forResource: "questions", withExtension: "json") else {
            print("[BundledQuestionStore] questions.json missing from bundle")
            all = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            all = try JSONDecoder().decode([TriviaQuestion].self, from: data)
            print("[BundledQuestionStore] Loaded \(all.count) offline questions")
        } catch {
            // Never fatal — the app must still launch without an offline floor.
            print("[BundledQuestionStore] Failed to decode questions.json: \(error)")
            all = []
        }
    }

    var isEmpty: Bool { all.isEmpty }

    /// Offline questions for a slot, best-effort.
    ///
    /// Falls back progressively rather than returning nothing: an exact
    /// pack+difficulty match is preferred, then the pack alone, then anything at
    /// all. A slightly off-difficulty question the user can actually answer beats
    /// a blank screen with the alarm still ringing.
    func questions(
        forPack packId: String,
        difficulty: Difficulty,
        excluding: Set<String> = []
    ) -> [TriviaQuestion] {
        let available = all.filter { !excluding.contains($0.id) }
        guard !available.isEmpty else { return [] }

        let exact = available.filter { $0.packId == packId && $0.difficulty == difficulty }
        if !exact.isEmpty { return exact }

        let samePack = available.filter { $0.packId == packId }
        if !samePack.isEmpty { return samePack }

        return available
    }

    /// Offline replacement after a wrong answer, honouring the different-book rule
    /// where possible but never returning nil if anything is left.
    func replacement(
        after missed: TriviaQuestion,
        packId: String,
        difficulty: Difficulty,
        excluding: Set<String>
    ) -> TriviaQuestion? {
        let pool = questions(forPack: packId, difficulty: difficulty, excluding: excluding)
        return pool.filter { $0.book != missed.book }.randomElement()
            ?? pool.randomElement()
    }
}
