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

    // MARK: - State

    private(set) var phase: Phase = .ringing
    private(set) var currentQuestion: TriviaQuestion?
    private(set) var lastMissedQuestion: TriviaQuestion?
    private(set) var totalSteps: Int = 3
    private(set) var completedSteps: Int = 0

    private var shownIds: Set<String> = []

    var fillPickedIndex: Int? = nil

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

    func begin() {
        triviaService.resetSession()
        shownIds = []
        lastMissedQuestion = nil
        completedSteps = 0
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

        if picked == q.answerIndex {
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

    // MARK: - Private helpers

    /// Called from CorrectMomentView after the celebration modal is dismissed.
    func continueFromMoment() {
        guard case .correctMoment(let step) = phase else { return }
        phase = .reveal(step: step)
    }

    private func handleCorrect(step: Int) {
        triviaService.markSeen(currentQuestion!)
        completedSteps += 1
        fillPickedIndex = nil
        phase = .correctMoment(step: step)
    }

    private func handleWrong(missed: TriviaQuestion, step: Int) {
        triviaService.markSeen(missed)
        shownIds.insert(missed.id)
        lastMissedQuestion = missed
        fillPickedIndex = nil

        let replacement = triviaService.replacementQuestion(
            after: missed,
            packId: alarm.packId,
            difficulty: alarm.difficulty,
            excluding: shownIds
        )
        currentQuestion = replacement
        if let r = replacement { shownIds.insert(r.id) }
    }

    private func loadQuestion(forStep step: Int) {
        let q = triviaService.question(
            forStep: step,
            packId: alarm.packId,
            difficulty: alarm.difficulty,
            excluding: shownIds
        )
        currentQuestion = q
        if let q { shownIds.insert(q.id) }
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
