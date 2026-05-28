import Foundation

/// Manages the question bank and enforces the anti-cheese rule:
/// a missed question is never repeated — a different question
/// from a different book is always substituted.
///
/// Question priority
/// ─────────────────
/// 1. AI-generated questions from QuestionGeneratorAgent cache (validated)
/// 2. Static sample questions bundled with the app (always available)
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

        // Priority 1: AI-generated questions from the agent cache
        let generated = agent.questions(forPack: packId, difficulty: difficulty)
        let generatedPool = generated.filter {
            !excluding.contains($0.id) && !sessionUsedIds.contains($0.id)
        }
        if let q = generatedPool.randomElement() {
            agent.consume(q)   // remove from cache so it isn't reused
            return q
        }

        // Priority 2: Static samples — filter by pack + difficulty first
        let staticPool = TriviaQuestion.samples.filter {
            $0.packId == packId &&
            $0.difficulty == difficulty &&
            !excluding.contains($0.id) &&
            !sessionUsedIds.contains($0.id)
        }
        if let q = staticPool.randomElement() { return q }

        // Fallback: any static sample not yet excluded
        let anyPool = TriviaQuestion.samples.filter {
            $0.packId == packId && !excluding.contains($0.id)
        }
        if let q = anyPool.randomElement() { return q }

        return TriviaQuestion.samples.filter { !excluding.contains($0.id) }.randomElement()
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

        // Try AI cache first — different book required
        let generated = agent.questions(forPack: packId, difficulty: difficulty)
        let genDiffBook = generated.filter {
            $0.book != missed.book && !excl.contains($0.id)
        }
        if let q = genDiffBook.randomElement() {
            agent.consume(q)
            return q
        }

        // Fall back to static samples
        let staticDiffBook = TriviaQuestion.samples.filter {
            $0.packId == packId &&
            $0.book != missed.book &&
            !excl.contains($0.id)
        }
        if let q = staticDiffBook.randomElement() { return q }

        let anyPackDiffBook = TriviaQuestion.samples.filter {
            $0.book != missed.book && !excl.contains($0.id)
        }
        if let q = anyPackDiffBook.randomElement() { return q }

        return TriviaQuestion.samples.filter { !excl.contains($0.id) }.randomElement()
    }

    // MARK: - Session management

    func markSeen(_ question: TriviaQuestion) {
        sessionUsedIds.insert(question.id)
    }

    func resetSession() {
        sessionUsedIds = []
    }
}
