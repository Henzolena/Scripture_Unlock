import Foundation

// MARK: - Models

struct QuizOption: Decodable, Identifiable {
    let label: String   // "A", "B", "C", "D"
    let text:  String
    var id: String { label }
}

struct QuizQuestion: Decodable, Identifiable {
    let id:            Int
    let book:          String
    let bookName:      String
    let chapter:       Int
    let verseStart:    Int
    let verseEnd:      Int
    let verseRef:      String
    let language:      String
    let question:      String
    let options:       [QuizOption]
    let correctAnswer: String
    let explanation:   String?
    let difficulty:    String   // "beginner" | "intermediate" | "advanced"
    let source:        String   // "static" | "ai_generated"
    let isVerified:    Bool

    enum CodingKeys: String, CodingKey {
        case id, book, chapter, language, question, options, difficulty, source, explanation
        case bookName      = "book_name"
        case verseStart    = "verse_start"
        case verseEnd      = "verse_end"
        case verseRef      = "verse_ref"
        case correctAnswer = "correct_answer"
        case isVerified    = "is_verified"
    }
}

struct QuizAnswerResponse: Decodable {
    let questionId:    Int
    let selected:      String
    let correctAnswer: String
    let isCorrect:     Bool
    let explanation:   String?
    let verseRef:      String
    let book:          String
    let chapter:       Int

    enum CodingKeys: String, CodingKey {
        case selected, explanation, book, chapter
        case questionId    = "question_id"
        case correctAnswer = "correct_answer"
        case isCorrect     = "is_correct"
        case verseRef      = "verse_ref"
    }
}

// MARK: - Private request / response wrappers

private struct QuizListResponse: Decodable {
    let questions: [QuizQuestion]
}

private struct GenerateRequest: Encodable {
    let book:       String
    let chapter:    Int
    let verseStart: Int
    let verseEnd:   Int
    let count:      Int
    let difficulty: String
    let language:   String
    let save:       Bool

    enum CodingKeys: String, CodingKey {
        case book, chapter, count, difficulty, language, save
        case verseStart = "verse_start"
        case verseEnd   = "verse_end"
    }
}

// Generate response may be wrapped {"questions":[...]} or bare [...].
private struct GenerateResponse: Decodable {
    let questions: [QuizQuestion]
}

private struct AnswerRequest: Encodable {
    let questionId: Int
    let selected:   String

    enum CodingKeys: String, CodingKey {
        case selected
        case questionId = "question_id"
    }
}

// MARK: - QuizService

final class QuizService {

    static let shared = QuizService()
    private init() {}

    private let baseURL = "https://ethiopian-bible-api-production.up.railway.app/api/v1/quiz"
    private let session = URLSession.shared

    // MARK: - Fetch stored questions for a verse

    /// Returns up to 10 static questions for the given verse.
    /// Falls back to chapter-level questions if the verse endpoint returns nothing.
    func questions(lang: String, book: String, chapter: Int, verse: Int) async -> [QuizQuestion] {
        // Try verse-specific first
        if let qs = await _fetch(path: "\(baseURL)/\(lang)/books/\(book)/\(chapter)/\(verse)?page_size=10"),
           !qs.isEmpty {
            return qs
        }
        // Fallback: chapter-level, filter client-side to verses near this one
        if let qs = await _fetch(path: "\(baseURL)/\(lang)/books/\(book)/\(chapter)?page_size=50") {
            return qs.filter { $0.verseStart <= verse && $0.verseEnd >= verse }
        }
        return []
    }

    private func _fetch(path: String) async -> [QuizQuestion]? {
        guard let url = URL(string: path) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(QuizListResponse.self, from: data).questions
        } catch {
            return nil
        }
    }

    // MARK: - AI-generate questions

    /// Asks the Gemini-powered endpoint to generate `count` questions for a
    /// verse range. Pass `save: true` to persist them so they have real IDs.
    func generateQuestions(
        book:      String,
        chapter:   Int,
        verseStart: Int,
        verseEnd:   Int,
        language:  String,
        count:     Int    = 5,
        save:      Bool   = true
    ) async -> [QuizQuestion] {
        guard let url = URL(string: "\(baseURL)/generate") else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45   // Gemini can be slow on first call

        let body = GenerateRequest(
            book: book, chapter: chapter,
            verseStart: verseStart, verseEnd: verseEnd,
            count: count, difficulty: "mixed",
            language: language, save: save
        )
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            // Try wrapped {"questions":[...]} first, then bare array
            if let result = try? JSONDecoder().decode(GenerateResponse.self, from: data) {
                return result.questions
            }
            return (try? JSONDecoder().decode([QuizQuestion].self, from: data)) ?? []
        } catch {
            print("[QuizService] generate error: \(error)")
            return []
        }
    }

    // MARK: - Submit answer

    func submitAnswer(questionId: Int, selected: String) async -> QuizAnswerResponse? {
        guard let url = URL(string: "\(baseURL)/answer") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(AnswerRequest(questionId: questionId, selected: selected))

        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(QuizAnswerResponse.self, from: data)
        } catch { return nil }
    }
}
