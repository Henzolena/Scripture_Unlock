import Foundation
import SwiftData

/// The core state machine for a morning trivia session.
/// Governs the full flow: ring → question → wrong/replacement → correct → reveal → next → dismissed.
///
/// Anti-cheese guarantee: a missed question is NEVER retried.
/// replacementQuestion() always returns a question from a different book.
@Observable
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
    /// True while waiting for the AI question cache to populate.
    private(set) var isGeneratingQuestions: Bool = false

    private var shownIds: Set<String> = []
    private var questionPollingTask: Task<Void, Never>?

    var fillPickedIndex: Int? = nil

    /// Language code for translated quiz content ("am", "or", "ti", or "" = English only)
    private(set) var parallelLanguage: String = ""

    /// Translated fill data keyed by question ID. Populated async after each question loads.
    private(set) var translatedFills: [String: TranslatedFill] = [:]

    private let alarm: Alarm
    private let triviaService: TriviaService
    private let alarmService: AlarmService

    // MARK: - Init

    init(alarm: Alarm,
         triviaService: TriviaService = .shared,
         alarmService: AlarmService = .shared) {
        self.alarm = alarm
        self.triviaService = triviaService
        self.alarmService = alarmService
        self.totalSteps = alarm.effectiveQuestionCount
    }

    // MARK: - Actions

    /// Call with the user's selected `parallelLanguage` from UserProfile.
    func begin(language: String = "") {
        parallelLanguage = language
        triviaService.resetSession()
        shownIds = []
        lastMissedQuestion = nil
        completedSteps = 0
        totalAttempts  = 0
        translatedFills = [:]
        loadQuestion(forStep: 0)
        phase = .question(step: 0)
    }

    func submitMCQ(pickedIndex: Int) {
        guard case .question(let step) = phase,
              let q = currentQuestion else { return }

        if pickedIndex == q.answerIndex {
            handleCorrect(step: step)
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
            handleCorrect(step: step)
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
        }
    }

    func silenceAlarm() {
        phase = .dismissed
        Task { await alarmService.dismissAlarm(alarm) }
    }

    /// Called from CorrectMomentView after the celebration modal is dismissed.
    func continueFromMoment() {
        guard case .correctMoment(let step) = phase else { return }
        phase = .reveal(step: step)
    }

    // MARK: - Private helpers

    private func handleCorrect(step: Int) {
        triviaService.markSeen(currentQuestion!)
        completedSteps += 1
        totalAttempts  += 1
        fillPickedIndex = nil
        phase = .correctMoment(step: step)
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
            shownIds.insert(q.id)
            prefetchTranslation(for: q)
        } else {
            // Cache empty — generation is running in background; poll until a question arrives.
            startPollingForQuestion(step: step)
        }
    }

    /// Polls the trivia cache every 2 seconds until a question is available.
    /// Stops automatically once a question loads or the phase changes.
    private func startPollingForQuestion(step: Int) {
        isGeneratingQuestions = true
        questionPollingTask?.cancel()
        questionPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 s
                guard let self, case .question = self.phase else { return }
                await MainActor.run {
                    let q = self.triviaService.question(
                        forStep: step,
                        packId: self.alarm.packId,
                        difficulty: self.alarm.difficulty,
                        excluding: self.shownIds
                    )
                    if let q {
                        self.currentQuestion = q
                        self.isGeneratingQuestions = false
                        self.shownIds.insert(q.id)
                        self.prefetchTranslation(for: q)
                        self.questionPollingTask?.cancel()
                    }
                }
            }
        }
    }

    // MARK: - Translation prefetch

    private func prefetchTranslation(for question: TriviaQuestion) {
        guard !parallelLanguage.isEmpty, question.kind == .fill else { return }
        let qId  = question.id
        let lang = parallelLanguage
        let ref  = question.verseRef

        Task {
            guard let verseText = await EthiopianBibleService.shared.verse(ref: ref, language: lang) else { return }
            if let fill = buildTranslatedFill(from: verseText, question: question) {
                await MainActor.run { self.translatedFills[qId] = fill }
            }
        }
    }

    /// Rebuild a fill question from a translated verse.
    ///
    /// Strategy: the blank falls at the same *word index* as in the English verse
    /// (determined by counting words in fillPre). Works well for Amharic, Oromo,
    /// and Tigrigna translations that preserve similar sentence structure.
    private func buildTranslatedFill(from translatedText: String, question: TriviaQuestion) -> TranslatedFill? {
        guard question.kind == .fill else { return nil }

        // How many words precede the blank in the English verse?
        let preWordCount = (question.fillPre ?? "")
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }.count

        // Split translated verse into words
        let words = translatedText
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        guard preWordCount < words.count else { return nil }

        let blankWord = words[preWordCount]
        let pre  = words[..<preWordCount].joined(separator: " ")
        let post = preWordCount + 1 < words.count
            ? words[(preWordCount + 1)...].joined(separator: " ")
            : ""

        // Build 3 unique distractors from other words in the verse
        var seen = Set<String>([blankWord])
        var distractors: [String] = []
        for word in words.shuffled() {
            guard !seen.contains(word), !word.isEmpty else { continue }
            seen.insert(word)
            distractors.append(word)
            if distractors.count == 3 { break }
        }

        // Need at least 3 distractors for a meaningful question
        guard distractors.count == 3 else { return nil }

        // Shuffle options so the correct answer isn't always last
        var options = distractors + [blankWord]
        options.shuffle()
        let answerIndex = options.firstIndex(of: blankWord) ?? 0

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
