import Foundation

struct PreparedStudyGuide: Codable, Equatable {
    let read: StudyGuideRead
    let reflect: StudyGuideReflect
    let discuss: StudyGuideDiscuss
    let quiz: StudyGuideQuiz
    let pray: StudyGuidePray
    let recap: StudyGuideRecap
}

struct StudyGuideRead: Codable, Equatable {
    let summary: String
    let context: String
    let keyObservations: [String]
    let keyTerms: [StudyGuideTerm]

    enum CodingKeys: String, CodingKey {
        case summary, context
        case keyObservations = "key_observations"
        case keyTerms = "key_terms"
    }
}

struct StudyGuideTerm: Codable, Equatable, Identifiable {
    let term: String
    let meaning: String

    var id: String { "\(term)-\(meaning)" }
}

struct StudyGuideReflect: Codable, Equatable {
    let devotional: String
    let personalQuestions: [String]
    let application: String

    enum CodingKeys: String, CodingKey {
        case devotional, application
        case personalQuestions = "personal_questions"
    }
}

struct StudyGuideDiscuss: Codable, Equatable {
    let openingQuestion: String
    let discussionQuestions: [String]
    let leaderNotes: [String]

    enum CodingKeys: String, CodingKey {
        case openingQuestion = "opening_question"
        case discussionQuestions = "discussion_questions"
        case leaderNotes = "leader_notes"
    }
}

struct StudyGuideQuiz: Codable, Equatable {
    let questions: [StudyGuideQuizQuestion]
}

struct StudyGuideQuizQuestion: Codable, Equatable, Identifiable {
    let question: String
    let options: [String]
    let answerIndex: Int
    let explanation: String

    var id: String { question }

    enum CodingKeys: String, CodingKey {
        case question, options, explanation
        case answerIndex = "answer_index"
    }
}

struct StudyGuidePray: Codable, Equatable {
    let prayerPoints: [String]
    let guidedPrayer: String

    enum CodingKeys: String, CodingKey {
        case prayerPoints = "prayer_points"
        case guidedPrayer = "guided_prayer"
    }
}

struct StudyGuideRecap: Codable, Equatable {
    let mainTakeaway: String
    let memoryPhrase: String
    let nextStep: String
    let closingSummary: String

    enum CodingKeys: String, CodingKey {
        case mainTakeaway = "main_takeaway"
        case memoryPhrase = "memory_phrase"
        case nextStep = "next_step"
        case closingSummary = "closing_summary"
    }
}

struct StudyGuideAPIError: Decodable {
    let errorCode: String
    let message: String
    let hint: String?

    enum CodingKeys: String, CodingKey {
        case message, hint
        case errorCode = "error_code"
    }
}

enum StudyGuideError: LocalizedError {
    case invalidURL
    case api(StudyGuideAPIError)
    case server(Int)
    case empty

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Study guide API is not configured."
        case .api(let error):
            if let hint = error.hint, !hint.isEmpty {
                return "\(error.message) \(hint)"
            }
            return error.message
        case .server(let status):
            return "Study guide request failed (HTTP \(status))."
        case .empty:
            return "Study guide response was empty."
        }
    }
}

final class StudyGuideService {
    static let shared = StudyGuideService()

    private let baseURL = "https://ethiopian-bible-api-production.up.railway.app/api/v1/study-guide"
    private let session = URLSession.shared
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private init() {}

    func generate(for sessionInfo: StudySessionInfo) async throws -> PreparedStudyGuide {
        guard let url = URL(string: "\(baseURL)/generate") else {
            throw StudyGuideError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try encoder.encode(
            GenerateStudyGuideRequest(
                book: sessionInfo.book.isEmpty ? sessionInfo.bookName : sessionInfo.book,
                chapter: sessionInfo.chapter,
                verseStart: sessionInfo.verseStart,
                verseEnd: sessionInfo.verseEnd,
                language: sessionInfo.language.isEmpty ? "niv" : sessionInfo.language
            )
        )

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode == 200 {
            let decoded = try decoder.decode(StudyGuideResponse.self, from: data)
            return decoded.guide
        }

        if let envelope = try? decoder.decode(StudyGuideErrorEnvelope.self, from: data) {
            throw StudyGuideError.api(envelope.detail)
        }

        if data.isEmpty {
            throw StudyGuideError.empty
        }

        throw StudyGuideError.server(statusCode)
    }
}

private struct GenerateStudyGuideRequest: Encodable {
    let book: String
    let chapter: Int
    let verseStart: Int?
    let verseEnd: Int?
    let language: String

    enum CodingKeys: String, CodingKey {
        case book, chapter, language
        case verseStart = "verse_start"
        case verseEnd = "verse_end"
    }
}

private struct StudyGuideResponse: Decodable {
    let guide: PreparedStudyGuide
}

private struct StudyGuideErrorEnvelope: Decodable {
    let detail: StudyGuideAPIError
}
