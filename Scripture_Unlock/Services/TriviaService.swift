import Foundation

/// Manages the question bank and enforces the anti-cheese rule:
/// a missed question is never repeated — a different question
/// from a different book is always substituted.
///
/// Question priority
/// ─────────────────
/// 1. AI-generated questions from QuestionGeneratorAgent cache (Railway API or Gemini)
/// 2. Bundled offline questions from BundledQuestionStore
///
/// Tier 2 exists because tier 1 needs the network both to generate *and* to
/// validate, while used questions are consumed permanently. Without a floor the
/// cache eventually empties and the alarm can no longer be silenced. These
/// methods therefore only return nil when the bundle is empty too.
///
/// The agent is asked to prefetch more questions whenever the cache is low;
/// this never blocks question delivery.
@Observable
final class TriviaService {

    static let shared = TriviaService()

    /// Questions shown in the current morning session (reset each day).
    private var sessionUsedIds: Set<String> = []

    private let agent  = QuestionGeneratorAgent.shared
    private let bundle = BundledQuestionStore.shared

    private init() {}

    // MARK: - Question selection

    func question(
        forStep step: Int,
        packId: String,
        difficulty: Difficulty,
        excluding: Set<String> = []
    ) -> TriviaQuestion? {
        // Kick off background generation so the cache stays warm for next time
        agent.prefetchIfNeeded(forPack: packId, difficulty: difficulty)

        let blocked = excluding.union(sessionUsedIds)

        // Tier 1 — AI-generated questions (Railway API or Gemini fallback)
        let generatedPool = agent.questions(forPack: packId, difficulty: difficulty)
            .filter { !blocked.contains($0.id) }
        if let q = generatedPool.randomElement() {
            agent.consume(q)   // remove from cache so it isn't reused
            return q.shuffledOptions()
        }

        // Tier 2 — bundled offline questions. Not consumed, so this tier can
        // never run dry within a session beyond its own exclusion set.
        if let q = bundle.questions(forPack: packId, difficulty: difficulty, excluding: blocked)
            .randomElement() {
            print("[TriviaService] AI cache empty — serving bundled offline question")
            return q.shuffledOptions()
        }

        return nil
    }

    /// Anti-cheese: pick a replacement after a wrong answer.
    /// Prefers a different book than the missed question.
    func replacementQuestion(
        after missed: TriviaQuestion,
        packId: String,
        difficulty: Difficulty,
        excluding: Set<String>
    ) -> TriviaQuestion? {
        var excl = excluding.union(sessionUsedIds)
        excl.insert(missed.id)

        let generated = agent.questions(forPack: packId, difficulty: difficulty)

        // Tier 1a — AI cache, different book required
        let genDiffBook = generated.filter { $0.book != missed.book && !excl.contains($0.id) }
        if let q = genDiffBook.randomElement() {
            agent.consume(q)
            return q.shuffledOptions()
        }

        // Tier 1b — any cached question (different-book preference exhausted)
        if let q = generated.filter({ !excl.contains($0.id) }).randomElement() {
            agent.consume(q)
            return q.shuffledOptions()
        }

        // Tier 2 — bundled offline questions
        if let q = bundle.replacement(after: missed, packId: packId,
                                      difficulty: difficulty, excluding: excl) {
            print("[TriviaService] AI cache empty — serving bundled offline replacement")
            return q.shuffledOptions()
        }

        return nil
    }

    // MARK: - Session management

    func markSeen(_ question: TriviaQuestion) {
        sessionUsedIds.insert(question.id)
    }

    func resetSession() {
        sessionUsedIds = []
    }
}
