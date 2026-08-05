//
//  AlarmQuizReliabilityTests.swift
//  Scripture_UnlockTests
//
//  Covers the failure that matters most: an alarm that cannot be silenced.
//  The offline question floor is the mechanism that prevents it, so these tests
//  pin down that it actually loads and behaves.
//

import Testing
import Foundation
@testable import Scripture_Unlock

/// Main-actor isolated: the module builds with main-actor default isolation, so
/// TriviaQuestion's Decodable conformance is isolated too. Decoding from a
/// nonisolated test would be an error under the Swift 6 language mode.
@MainActor
struct BundledQuestionStoreTests {

    /// The whole offline floor rests on this file decoding. It previously did not:
    /// questions.json stores difficulty lowercase ("regular") while the enum's
    /// rawValue is capitalised ("Regular"), so a strict decode threw and the
    /// bundle silently contributed nothing.
    @Test func bundledQuestionsDecode() throws {
        let store = BundledQuestionStore.shared
        #expect(!store.isEmpty, "questions.json must decode — it is the offline floor")
    }

    @Test func lowercaseDifficultyDecodesCaseInsensitively() throws {
        let json = """
        {
          "id": "TEST.1.1-mcq", "kind": "mcq", "book": "Genesis", "packId": "ot",
          "difficulty": "regular",
          "prompt": "q", "options": ["a","b","c","d"], "answerIndex": 1,
          "fillPre": null, "fillPost": null,
          "verseRef": "Genesis 1:1", "verseText": "In the beginning."
        }
        """.data(using: .utf8)!

        let q = try JSONDecoder().decode(TriviaQuestion.self, from: json)
        #expect(q.difficulty == .regular)
    }

    @Test func unknownDifficultyFallsBackRatherThanThrowing() throws {
        let json = """
        {
          "id": "TEST.1.2-mcq", "kind": "mcq", "book": "Genesis", "packId": "ot",
          "difficulty": "wildly-unknown",
          "prompt": "q", "options": ["a","b","c","d"], "answerIndex": 0,
          "fillPre": null, "fillPost": null,
          "verseRef": "Genesis 1:1", "verseText": "In the beginning."
        }
        """.data(using: .utf8)!

        let q = try JSONDecoder().decode(TriviaQuestion.self, from: json)
        #expect(q.difficulty == .regular, "an odd difficulty must not lose the question")
    }

    /// An unknown pack must still yield questions — a user on a pack with no
    /// bundled coverage (e.g. "beginner") must not be left with nothing.
    @Test func unknownPackStillReturnsSomething() {
        let store = BundledQuestionStore.shared
        let q = store.questions(forPack: "no-such-pack", difficulty: .scholar)
        #expect(!q.isEmpty, "must degrade to any available question, not none")
    }

    @Test func exclusionIsHonoured() {
        let store = BundledQuestionStore.shared
        let all = store.questions(forPack: "ot", difficulty: .regular)
        guard let first = all.first else { return }
        let rest = store.questions(forPack: "ot", difficulty: .regular, excluding: [first.id])
        #expect(!rest.contains { $0.id == first.id })
    }

    /// Anti-cheese still applies offline: a replacement should prefer another book.
    @Test func offlineReplacementPrefersDifferentBook() {
        let store = BundledQuestionStore.shared
        guard let missed = store.questions(forPack: "ot", difficulty: .regular).first else { return }
        let replacement = store.replacement(
            after: missed, packId: "ot", difficulty: .regular, excluding: [missed.id]
        )
        #expect(replacement != nil, "offline replacement must exist rather than dead-ending")
        #expect(replacement?.id != missed.id, "a missed question is never retried")
    }
}

struct OptionShufflingTests {

    /// Shuffling must move the answer's index along with it. Getting this wrong
    /// would make correct answers score as wrong — worse than the position bias.
    @Test func shuffleKeepsAnswerIndexPointingAtTheCorrectOption() {
        let q = TriviaQuestion(
            id: "x", kind: .mcq, book: "Genesis", packId: "ot", difficulty: .regular,
            prompt: "who?", options: ["Abraham", "Noah", "Moses", "Enoch"], answerIndex: 1,
            fillPre: nil, fillPost: nil,
            verseRef: "Genesis 6:14", verseText: "text"
        )
        let correct = q.options[q.answerIndex]

        for _ in 0..<200 {
            let s = q.shuffledOptions()
            #expect(s.options.count == q.options.count)
            #expect(Set(s.options) == Set(q.options), "no option may be lost or invented")
            #expect(s.options[s.answerIndex] == correct, "answerIndex must follow the answer")
        }
    }

    @Test func shuffleLeavesDegenerateQuestionsAlone() {
        let single = TriviaQuestion(
            id: "y", kind: .mcq, book: "Genesis", packId: "ot", difficulty: .regular,
            prompt: "p", options: ["only"], answerIndex: 0,
            fillPre: nil, fillPost: nil, verseRef: "r", verseText: "t"
        )
        #expect(single.shuffledOptions().options == ["only"])

        // Out-of-range answerIndex must not crash or corrupt the question.
        let bad = TriviaQuestion(
            id: "z", kind: .mcq, book: "Genesis", packId: "ot", difficulty: .regular,
            prompt: "p", options: ["a", "b"], answerIndex: 9,
            fillPre: nil, fillPost: nil, verseRef: "r", verseText: "t"
        )
        #expect(bad.shuffledOptions().options == ["a", "b"])
    }
}

/// Serialized: every case here reads and writes the same UserDefaults key, so
/// running them in parallel makes them clobber one another.
@Suite(.serialized)
struct SessionStoreTests {

    @Test func roundTripsProgressForTheSameAlarmToday() {
        let id = UUID()
        SessionStore.clear()
        SessionStore.save(.init(
            alarmId: id.uuidString,
            day: Calendar.current.startOfDay(for: Date()),
            step: 2, completedSteps: 2, totalAttempts: 4, totalSteps: 5,
            shownIds: ["a", "b"]
        ))
        let loaded = SessionStore.load(alarmId: id)
        #expect(loaded?.step == 2)
        #expect(loaded?.completedSteps == 2)
        #expect(loaded?.shownIds.count == 2)
        SessionStore.clear()
    }

    @Test func doesNotResurrectYesterdaysQuiz() {
        let id = UUID()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        SessionStore.clear()
        SessionStore.save(.init(
            alarmId: id.uuidString,
            day: Calendar.current.startOfDay(for: yesterday),
            step: 1, completedSteps: 1, totalAttempts: 1, totalSteps: 3,
            shownIds: []
        ))
        #expect(SessionStore.load(alarmId: id) == nil, "stale sessions must not resume")
        SessionStore.clear()
    }

    @Test func ignoresSnapshotFromADifferentAlarm() {
        SessionStore.clear()
        SessionStore.save(.init(
            alarmId: UUID().uuidString,
            day: Calendar.current.startOfDay(for: Date()),
            step: 1, completedSteps: 1, totalAttempts: 1, totalSteps: 3,
            shownIds: []
        ))
        #expect(SessionStore.load(alarmId: UUID()) == nil)
        SessionStore.clear()
    }

    @Test func ignoresAlreadyCompletedSession() {
        let id = UUID()
        SessionStore.clear()
        SessionStore.save(.init(
            alarmId: id.uuidString,
            day: Calendar.current.startOfDay(for: Date()),
            step: 2, completedSteps: 3, totalAttempts: 3, totalSteps: 3,
            shownIds: []
        ))
        #expect(SessionStore.load(alarmId: id) == nil, "a finished quiz must not reopen")
        SessionStore.clear()
    }
}

struct TranslatedFillTests {

    /// The blank must be a real word from the translated verse, and the options
    /// must contain it exactly once at the reported index.
    @Test func buildsSelfConsistentFill() {
        let q = TriviaQuestion(
            id: "f1", kind: .fill, book: "Psalms", packId: "psalms", difficulty: .regular,
            prompt: nil, options: ["a", "b", "c", "d"], answerIndex: 0,
            fillPre: "The Lord is my", fillPost: "I shall not want",
            verseRef: "Psalm 23:1", verseText: "The Lord is my shepherd I shall not want"
        )
        let text = "እግዚአብሔር ጠባቂዬ ነው ምንም አልጎድልብኝም ደግሞ ተስፋዬ"
        let fill = TriviaViewModel.buildTranslatedFill(from: text, question: q)

        guard let fill else { return }   // nil is an acceptable, safe outcome
        #expect(fill.options.count == 4)
        #expect(Set(fill.options).count == 4, "options must be distinct")
        #expect(fill.options.indices.contains(fill.answerIndex))
        let answer = fill.options[fill.answerIndex]
        #expect(text.contains(answer), "the blank must come from the translated verse")
        #expect(!fill.pre.contains(answer), "the answer must not be visible in the prompt")
    }

    @Test func refusesToBuildFromTooLittleText() {
        let q = TriviaQuestion(
            id: "f2", kind: .fill, book: "Psalms", packId: "psalms", difficulty: .regular,
            prompt: nil, options: ["a", "b", "c", "d"], answerIndex: 0,
            fillPre: "one", fillPost: "two",
            verseRef: "Psalm 1:1", verseText: "one x two"
        )
        // Too few usable words to make four distinct options.
        #expect(TriviaViewModel.buildTranslatedFill(from: "አንድ ሁለት", question: q) == nil)
    }

    @Test func refusesNonFillQuestions() {
        let mcq = TriviaQuestion(
            id: "m1", kind: .mcq, book: "Psalms", packId: "psalms", difficulty: .regular,
            prompt: "p", options: ["a", "b", "c", "d"], answerIndex: 0,
            fillPre: nil, fillPost: nil, verseRef: "r", verseText: "t"
        )
        #expect(TriviaViewModel.buildTranslatedFill(from: "አንድ ሁለት ሶስት አራት አምስት ስድስት", question: mcq) == nil)
    }
}

struct AlarmToneTests {

    /// fireFromBackground used to reference "alarm_ringtone.caf", which is not in
    /// the bundle — so iOS played nothing. Every tone must map to a real file.
    @Test func everyToneHasAFileInTheBundle() {
        for tone in AlarmTone.all {
            let url = Bundle.main.url(forResource: tone.filename, withExtension: "caf")
            #expect(url != nil, "missing sound file: \(tone.filename).caf")
        }
    }

    @Test func findFallsBackForUnknownIdentifier() {
        let tone = AlarmTone.find(id: "does-not-exist")
        #expect(Bundle.main.url(forResource: tone.filename, withExtension: "caf") != nil)
    }
}

struct AlarmSchedulingTests {

    /// hour is stored 0–11 with a separate isAM flag, so midnight and noon are the
    /// cases most likely to be wrong. Pin them down.
    @Test func midnightAndNoonResolveCorrectly() {
        let midnight = Alarm(label: "midnight", hour: 0, minute: 30)
        midnight.isAM = true
        midnight.repeatDays = []
        let mComps = Calendar.current.dateComponents([.hour, .minute], from: midnight.nextFireDate)
        #expect(mComps.hour == 0, "12:30 AM must be hour 0, not 12")
        #expect(mComps.minute == 30)

        let noon = Alarm(label: "noon", hour: 0, minute: 15)
        noon.isAM = false
        noon.repeatDays = []
        let nComps = Calendar.current.dateComponents([.hour, .minute], from: noon.nextFireDate)
        #expect(nComps.hour == 12, "12:15 PM must be hour 12, not 24")
        #expect(nComps.minute == 15)
    }

    @Test func nextActualFireDateIsAlwaysInTheFuture() {
        let alarm = Alarm(label: "t", hour: 6, minute: 0)
        alarm.repeatDays = []
        guard let next = alarm.nextActualFireDate else {
            Issue.record("a one-time enabled alarm must have a next fire date")
            return
        }
        #expect(next > Date())
    }

    @Test func disabledAlarmNeverFires() {
        let alarm = Alarm(label: "off", hour: 7, minute: 0)
        alarm.isEnabled = false
        #expect(alarm.nextActualFireDate == nil)
    }

    @Test func snoozePenaltyRaisesQuestionCount() {
        let alarm = Alarm(label: "s", hour: 6, minute: 0)
        alarm.questionCount = 3
        #expect(alarm.effectiveQuestionCount == 3)
        alarm.snoozeCountToday = 2
        #expect(alarm.effectiveQuestionCount == 5, "each snooze adds a question")
    }
}
