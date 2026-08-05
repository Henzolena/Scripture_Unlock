import Foundation
import SwiftData

/// The core state machine for a morning trivia session.
/// Governs the full flow: ring → question → wrong/replacement → correct → reveal → next → dismissed.
///
/// Anti-cheese guarantee: a missed question is NEVER retried.
/// replacementQuestion() always prefers a question from a different book.
@Observable
@MainActor
final class TriviaViewModel {

    // MARK: - Phase

    enum Phase: Equatable {
        case ringing
        case question(step: Int)
        case correctMoment(step: Int)   // celebration modal between answer and reveal
        case reveal(step: Int)
        case dismissed
    }

    // MARK: - Translated fill

    /// Reconstructed fill structure for a question when a parallel language is active.
    struct TranslatedFill {
        let pre:         String
        let post:        String
        let options:     [String]   // shuffled; includes correct answer
        let answerIndex: Int        // index of correct answer in `options`
    }

    // MARK: - State

    private(set) var phase: Phase = .ringing
    private(set) var currentQuestion: TriviaQuestion?
    private(set) var lastMissedQuestion: TriviaQuestion?
    private(set) var totalSteps: Int = 3
    private(set) var completedSteps: Int = 0
    /// Total attempts including wrong answers (for accuracy tracking).
    private(set) var totalAttempts: Int = 0
    /// True while waiting for the question cache to populate.
    private(set) var isGeneratingQuestions: Bool = false
    /// Set when every question source has failed. Unlocks the escape hatch so the
    /// user is never physically trapped by a ringing alarm they cannot silence.
    private(set) var questionSourcesExhausted: Bool = false
    /// Snapshot of the alarm's snooze count taken at dismiss time, before
    /// `dismissAlarm` clears it, so the streak entry records the real value.
    private(set) var snoozeCountAtDismiss: Int = 0

    private var shownIds: Set<String> = []
    private var questionPollingTask: Task<Void, Never>?
    private var hasBegun = false

    /// How long to wait for a question before offering the escape hatch.
    private let maxPollAttempts = 8      // × 2 s ≈ 16 s

    var fillPickedIndex: Int? = nil

    /// Language code for translated quiz content ("am", "or", "ti", or "" = English only)
    private(set) var parallelLanguage: String = ""

    /// Translated fill data keyed by question ID. Populated async after each question loads.
    private(set) var translatedFills: [String: TranslatedFill] = [:]

    private let alarm: Alarm
    private let triviaService: TriviaService
    private let alarmService: AlarmService

    // MARK: - Init

    /// Services default to their shared instances. They are resolved inside the
    /// initialiser rather than as default arguments, because default-argument
    /// expressions are evaluated in a nonisolated context at the call site and
    /// touching a main-actor-isolated `shared` from there is a concurrency error.
    init(alarm: Alarm,
         triviaService: TriviaService? = nil,
         alarmService: AlarmService? = nil) {
        self.alarm = alarm
        self.triviaService = triviaService ?? .shared
        self.alarmService = alarmService ?? .shared
        self.totalSteps = max(1, alarm.effectiveQuestionCount)
    }

    // MARK: - Actions

    /// Call with the user's selected `parallelLanguage` from UserProfile.
    ///
    /// Safe to call more than once — the view hierarchy can fire `onAppear` from
    /// two places, and re-running this would silently discard progress and burn a
    /// cached question.
    func begin(language: String = "") {
        guard !hasBegun else { return }
        hasBegun = true
        parallelLanguage = language
        triviaService.resetSession()
        translatedFills = [:]

        // Resume an interrupted session if the app was killed mid-quiz. Without
        // this a crash at 6 AM restarts the user from question one.
        if let saved = SessionStore.load(alarmId: alarm.id) {
            totalSteps     = max(1, saved.totalSteps)
            completedSteps = min(saved.completedSteps, totalSteps)
            totalAttempts  = saved.totalAttempts
            shownIds       = Set(saved.shownIds)
            let step = min(saved.step, totalSteps - 1)
            loadQuestion(forStep: step)
            phase = .question(step: step)
            print("[TriviaViewModel] Resumed session at step \(step + 1)/\(totalSteps)")
            return
        }

        shownIds = []
        lastMissedQuestion = nil
        completedSteps = 0
        totalAttempts  = 0
        loadQuestion(forStep: 0)
        phase = .question(step: 0)
        persist(step: 0)
    }

    func submitMCQ(pickedIndex: Int) {
        guard case .question(let step) = phase,
              let q = currentQuestion else { return }

        if pickedIndex == q.answerIndex {
            handleCorrect(question: q, step: step)
        } else {
            handleWrong(missed: q, step: step)
        }
    }

    func pickFillOption(index: Int) {
        fillPickedIndex = index
    }

    func confirmFill() {
        guard case .question(let step) = phase,
              let q = currentQuestion,
              let picked = fillPickedIndex else { return }

        // Use translated answer index when fill has been reconstructed in another language
        let correctIndex = translatedFills[q.id]?.answerIndex ?? q.answerIndex

        if picked == correctIndex {
            handleCorrect(question: q, step: step)
        } else {
            handleWrong(missed: q, step: step)
        }
    }

    func continueAfterReveal() {
        guard case .reveal(let step) = phase else { return }
        let nextStep = step + 1
        if nextStep >= totalSteps {
            silenceAlarm()
        } else {
            lastMissedQuestion = nil
            fillPickedIndex = nil
            loadQuestion(forStep: nextStep)
            phase = .question(step: nextStep)
            persist(step: nextStep)
        }
    }

    func silenceAlarm() {
        questionPollingTask?.cancel()
        SessionStore.clear()
        // Capture the snooze count before dismissAlarm resets it to zero. The
        // streak write reads this during the phase change, so reading the model
        // directly was a race that silently recorded zero snoozes.
        snoozeCountAtDismiss = alarm.snoozeCountToday
        phase = .dismissed
        Task { await alarmService.dismissAlarm(alarm) }
    }

    /// Escape hatch, only reachable once `questionSourcesExhausted` is true.
    ///
    /// A user who cannot produce a single question — no network, empty cache,
    /// empty bundle — must still be able to stop the noise. Trapping them behind
    /// a quiz that cannot load is worse than letting the alarm go.
    func forceSilenceAfterFailure() {
        guard questionSourcesExhausted else { return }
        print("[TriviaViewModel] Escape hatch used — no question source available")
        silenceAlarm()
    }

    /// Called from CorrectMomentView after the celebration modal is dismissed.
    func continueFromMoment() {
        guard case .correctMoment(let step) = phase else { return }
        phase = .reveal(step: step)
    }

    // MARK: - Private helpers

    private func handleCorrect(question: TriviaQuestion, step: Int) {
        triviaService.markSeen(question)
        completedSteps += 1
        totalAttempts  += 1
        fillPickedIndex = nil
        phase = .correctMoment(step: step)
        persist(step: step)
    }

    private func handleWrong(missed: TriviaQuestion, step: Int) {
        triviaService.markSeen(missed)
        shownIds.insert(missed.id)
        lastMissedQuestion = missed
        fillPickedIndex = nil
        totalAttempts += 1   // wrong attempt still counts

        let replacement = triviaService.replacementQuestion(
            after: missed,
            packId: alarm.packId,
            difficulty: alarm.difficulty,
            excluding: shownIds
        )
        currentQuestion = replacement

        if let r = replacement {
            shownIds.insert(r.id)
            prefetchTranslation(for: r)
            persist(step: step)
        } else {
            // No replacement available. Previously this left currentQuestion nil
            // with no polling and no UI branch, producing a blank screen with the
            // alarm still ringing and no way out.
            startPollingForQuestion(step: step)
        }
    }

    private func loadQuestion(forStep step: Int) {
        let q = triviaService.question(
            forStep: step,
            packId: alarm.packId,
            difficulty: alarm.difficulty,
            excluding: shownIds
        )
        currentQuestion = q
        if let q {
            isGeneratingQuestions = false
            questionSourcesExhausted = false
            shownIds.insert(q.id)
            prefetchTranslation(for: q)
        } else {
            startPollingForQuestion(step: step)
        }
    }

    /// Polls for a question every 2 seconds, giving background generation a chance
    /// to land. Bounded: after `maxPollAttempts` it stops and unlocks the escape
    /// hatch rather than spinning forever behind an un-dismissable alarm.
    private func startPollingForQuestion(step: Int) {
        isGeneratingQuestions = true
        questionSourcesExhausted = false
        questionPollingTask?.cancel()

        // Runs on the main actor (the type is @MainActor), so reads of `phase`
        // and the observable state below are not racing with the UI.
        questionPollingTask = Task { [weak self] in
            var attempts = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 s
                guard let self, case .question = self.phase else { return }

                if let q = self.triviaService.question(
                    forStep: step,
                    packId: self.alarm.packId,
                    difficulty: self.alarm.difficulty,
                    excluding: self.shownIds
                ) {
                    self.currentQuestion = q
                    self.isGeneratingQuestions = false
                    self.questionSourcesExhausted = false
                    self.shownIds.insert(q.id)
                    self.prefetchTranslation(for: q)
                    self.persist(step: step)
                    return
                }

                attempts += 1
                if attempts >= self.maxPollAttempts {
                    // Every tier failed. Surface it and let the user out.
                    self.isGeneratingQuestions = false
                    self.questionSourcesExhausted = true
                    print("[TriviaViewModel] No question after \(attempts) attempts — offering escape hatch")
                    return
                }
            }
        }
    }

    /// Retry after exhaustion — e.g. the user has just reconnected.
    func retryQuestionLoad() {
        guard case .question(let step) = phase else { return }
        questionSourcesExhausted = false
        loadQuestion(forStep: step)
    }

    // MARK: - Session persistence

    private func persist(step: Int) {
        SessionStore.save(.init(
            alarmId:        alarm.id.uuidString,
            day:            Calendar.current.startOfDay(for: Date()),
            step:           step,
            completedSteps: completedSteps,
            totalAttempts:  totalAttempts,
            totalSteps:     totalSteps,
            shownIds:       Array(shownIds)
        ))
    }

    // MARK: - Translation prefetch

    private func prefetchTranslation(for question: TriviaQuestion) {
        guard !parallelLanguage.isEmpty, question.kind == .fill else { return }
        let qId  = question.id
        let lang = parallelLanguage
        let ref  = question.verseRef

        Task { [weak self] in
            guard let verseText = await EthiopianBibleService.shared.verse(ref: ref, language: lang) else { return }
            guard let fill = Self.buildTranslatedFill(from: verseText, question: question) else { return }
            await MainActor.run { self?.translatedFills[qId] = fill }
        }
    }

    /// Rebuild a fill question from a translated verse.
    ///
    /// Important limitation: word order is not preserved across English, Amharic,
    /// Oromo and Tigrigna, so the blank cannot be aligned to the *same word* the
    /// English question blanked. What this builds instead is a self-consistent
    /// fill-in-the-blank in the target language — a real word from that verse, with
    /// distractors drawn from the same verse.
    ///
    /// It returns nil rather than producing a poor question (single-character
    /// particles, punctuation fragments, too few usable distractors); callers then
    /// fall back to showing the English question, which is always valid.
    nonisolated static func buildTranslatedFill(
        from translatedText: String,
        question: TriviaQuestion
    ) -> TranslatedFill? {
        guard question.kind == .fill else { return nil }

        // Strip punctuation so options are clean words, not "word," or "word."
        let punctuation = CharacterSet.punctuationCharacters.union(.symbols)
        let words = translatedText
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: punctuation) }
            .filter { $0.count >= 2 }

        // Need a blank plus three distinct distractors to be worth showing.
        guard words.count >= 6 else { return nil }

        // Choose the blank from the middle of the verse so there is context on
        // both sides, and prefer a substantial word over a short particle.
        let interior = Array(words.indices).filter { $0 > 0 && $0 < words.count - 1 }
        guard let blankIndex = interior
            .max(by: { words[$0].count < words[$1].count }) else { return nil }

        let blankWord = words[blankIndex]
        guard blankWord.count >= 3 else { return nil }

        let pre  = words[..<blankIndex].joined(separator: " ")
        let post = words[(blankIndex + 1)...].joined(separator: " ")

        // Distractors: unique, similar in length to the answer so length alone
        // is not a giveaway.
        var seen = Set([blankWord])
        let candidates = words.enumerated()
            .filter { $0.offset != blankIndex }
            .map(\.element)
            .filter { seen.insert($0).inserted }
            .sorted { abs($0.count - blankWord.count) < abs($1.count - blankWord.count) }

        let distractors = Array(candidates.prefix(3))
        guard distractors.count == 3 else { return nil }

        var options = distractors + [blankWord]
        options.shuffle()
        guard let answerIndex = options.firstIndex(of: blankWord) else { return nil }

        return TranslatedFill(pre: pre, post: post, options: options, answerIndex: answerIndex)
    }

    // MARK: - Computed helpers

    var currentStep: Int {
        if case .question(let s) = phase { return s }
        if case .reveal(let s) = phase   { return s }
        return 0
    }

    var isLastStep: Bool { currentStep == totalSteps - 1 }

    var progressFraction: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(completedSteps) / Double(totalSteps)
    }
}

// MARK: - Session persistence store

/// Persists mid-quiz progress so a crash, force-quit or OS termination does not
/// reset the user to question one while the alarm is still going.
enum SessionStore {

    struct Snapshot: Codable {
        let alarmId: String
        let day: Date
        let step: Int
        let completedSteps: Int
        let totalAttempts: Int
        let totalSteps: Int
        let shownIds: [String]
    }

    private static let key = "triviaSessionSnapshot"

    static func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Returns a snapshot only when it belongs to this alarm and to today —
    /// yesterday's half-finished quiz must not resurrect.
    static func load(alarmId: UUID) -> Snapshot? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.alarmId == alarmId.uuidString,
              Calendar.current.isDateInToday(snapshot.day),
              snapshot.completedSteps < snapshot.totalSteps
        else { return nil }
        return snapshot
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
