import Foundation

/// Manages the question bank and enforces the anti-cheese rule:
/// a missed question is never repeated — a different question
/// from a different book is always substituted.
///
/// Question priority
/// ─────────────────
/// 1. AI-generated questions from QuestionGeneratorAgent cache (Railway API or Gemini)
/// 2. Returns nil when cache is empty — the ViewModel shows a "Generating…" state
///
/// The agent is asked to prefetch more questions whenever the cache is low;
/// this never blocks question delivery.
@Observable
final class TriviaService {

    static let shared = TriviaService()

    /// Questions shown in the current morning session (reset each day).
    private var sessionUsedIds: Set<String> = []

    private let agent = QuestionGeneratorAgent.shared

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

        // AI-generated questions from the agent cache (Railway API or Gemini fallback)
        let generated = agent.questions(forPack: packId, difficulty: difficulty)
        let generatedPool = generated.filter {
            !excluding.contains($0.id) && !sessionUsedIds.contains($0.id)
        }
        if let q = generatedPool.randomElement() {
            agent.consume(q)   // remove from cache so it isn't reused
            return q
        }

        // Cache is empty — background generation was already triggered by prefetchIfNeeded.
        // Return nil so the ViewModel can show a "generating" state instead of a stale question.
        return nil
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

        // Try AI cache — different book required
        let generated = agent.questions(forPack: packId, difficulty: difficulty)
        let genDiffBook = generated.filter {
            $0.book != missed.book && !excl.contains($0.id)
        }
        if let q = genDiffBook.randomElement() {
            agent.consume(q)
            return q
        }

        // Try any cached question regardless of book (different book preference exhausted)
        let genAny = generated.filter { !excl.contains($0.id) }
        if let q = genAny.randomElement() {
            agent.consume(q)
            return q
        }

        // Cache is empty — return nil; ViewModel will show "generating" state
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
