import Foundation

// MARK: - Public models

struct QuizOption: Decodable, Identifiable {
    let label: String   // "A", "B", "C", "D"
    let text:  String
    var id: String { label }
}

struct QuizQuestion: Decodable, Identifiable {
    let id:            Int
    let groupId:       String?  // links same question across all 4 language translations
    let book:          String
    let bookName:      String
    let chapter:       Int
    let verseStart:    Int?     // nil for whole-chapter questions
    let verseEnd:      Int?     // nil for whole-chapter questions
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
        case groupId       = "group_id"
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

// MARK: - Structured API error (matches the new quiz router error shape)

/// Decoded from `{"detail": {"error": true, "error_code": "...", "message": "...", "hint": "..."}}`
struct QuizAPIError: Decodable {
    let errorCode: String
    let message:   String
    let hint:      String?

    enum CodingKeys: String, CodingKey {
        case message, hint
        case errorCode = "error_code"
    }
}

// MARK: - Generate result

/// Returned by `generateQuestions` so the caller can distinguish success
/// from specific API failures and show actionable UI.
enum QuizGenerateResult {
    case success([QuizQuestion])
    case apiError(QuizAPIError)     // structured error from server
    case networkError               // timeout / unreachable
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

/// Envelope for new structured errors: `{"detail": {object}}`.
private struct APIErrorEnvelope: Decodable {
    let detail: QuizAPIError
}

/// Envelope for legacy string errors: `{"detail": "Gemini API error 429: ..."}`.
private struct APIStringErrorEnvelope: Decodable {
    let detail: String
}

// MARK: - QuizService

final class QuizService {

    static let shared = QuizService()
    private init() {}

    private let baseURL = "https://ethiopian-bible-api-production.up.railway.app/api/v1/quiz"
    private let session = URLSession.shared

    // MARK: - Fetch stored questions for a chapter

    /// Returns stored questions for the chapter (up to 20).
    /// Returns `[]` when none exist yet — caller should then call `generateQuestions`.
    /// Returns `[]` on network error too; callers treat both the same way.
    func chapterQuestions(lang: String, book: String, chapter: Int) async -> [QuizQuestion] {
        await _fetch(path: "\(baseURL)/\(lang)/books/\(book)/\(chapter)?page_size=20") ?? []
    }

    // MARK: - Fetch stored questions for a verse (fallback helper)

    func questions(lang: String, book: String, chapter: Int, verse: Int) async -> [QuizQuestion] {
        if let qs = await _fetch(path: "\(baseURL)/\(lang)/books/\(book)/\(chapter)/\(verse)?page_size=10"),
           !qs.isEmpty {
            return qs
        }
        if let qs = await _fetch(path: "\(baseURL)/\(lang)/books/\(book)/\(chapter)?page_size=50") {
            let nearby = qs.filter {
                guard let vs = $0.verseStart, let ve = $0.verseEnd else { return true }
                return vs <= verse && ve >= verse
            }
            return nearby.isEmpty ? qs : nearby
        }
        return []
    }

    // MARK: - Internal fetch

    /// `nil`  → genuine network / decode error
    /// `[]`   → request succeeded but no questions (NO_QUESTIONS_FOUND 404)
    private func _fetch(path: String) async -> [QuizQuestion]? {
        guard let url = URL(string: path) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 200 {
                return try JSONDecoder().decode(QuizListResponse.self, from: data).questions
            }

            // Any 404 from the quiz endpoint means "no questions stored yet"
            // — regardless of whether the body is valid JSON — so return []
            // to signal the caller should try AI generation.
            if status == 404 { return [] }

            return nil
        } catch {
            return nil
        }
    }

    // MARK: - AI-generate questions

    /// Calls the Gemini-powered `/generate` endpoint.
    /// Returns a `QuizGenerateResult` so the caller can show tailored error UI.
    func generateQuestions(
        book:       String,
        chapter:    Int,
        verseStart: Int,
        verseEnd:   Int,
        language:   String,
        difficulty: String = "mixed",
        count:      Int  = 5,
        save:       Bool = true
    ) async -> QuizGenerateResult {
        guard let url = URL(string: "\(baseURL)/generate") else { return .networkError }

        var request = URLRequest(url: url)
        request.httpMethod  = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60   // Gemini can be slow; matches new API timeout

        let body = GenerateRequest(
            book: book, chapter: chapter,
            verseStart: verseStart, verseEnd: verseEnd,
            count: count, difficulty: difficulty,
            language: language, save: save
        )
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            // ── Success ──────────────────────────────────────────────────────
            if status == 200 {
                // Try wrapped {"questions":[...]} first, then bare [...]
                if let wrapped = try? JSONDecoder().decode(GenerateResponse.self, from: data),
                   !wrapped.questions.isEmpty {
                    return .success(wrapped.questions)
                }
                if let bare = try? JSONDecoder().decode([QuizQuestion].self, from: data),
                   !bare.isEmpty {
                    return .success(bare)
                }
                // 200 but no questions parsed
                return .apiError(QuizAPIError(
                    errorCode: "EMPTY_RESPONSE",
                    message:   "The server returned no questions for this chapter.",
                    hint:      "Try a different chapter or check back later."
                ))
            }

            // ── Structured API error — new format {"detail": {object}} ─────
            if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                return .apiError(envelope.detail)
            }

            // ── Legacy string-detail format — {"detail": "Gemini API error 429: …"} ──
            // The live API still returns plain strings for Gemini errors, so parse
            // the string to extract the right error code before falling back to
            // the generic HTTP-status mapping.
            if let strEnvelope = try? JSONDecoder().decode(APIStringErrorEnvelope.self, from: data) {
                return .apiError(Self.parseStringDetail(strEnvelope.detail, httpStatus: status))
            }

            // ── Railway / proxy-level error (body is HTML or empty) ──────────
            return .apiError(Self.fallbackError(forStatus: status))

        } catch is URLError {
            return .networkError
        } catch {
            print("[QuizService] generate error: \(error)")
            return .networkError
        }
    }

    // MARK: - String-detail parser (legacy API format)

    /// Converts a plain-string `detail` value into a structured `QuizAPIError`
    /// by scanning for known keywords in the raw Gemini/FastAPI error text.
    private static func parseStringDetail(_ detail: String, httpStatus: Int) -> QuizAPIError {
        let lower = detail.lowercased()

        // Rate-limit / quota from either Mistral or Gemini
        if lower.contains("429") || lower.contains("quota") || lower.contains("rate limit") {
            return QuizAPIError(
                errorCode: "AI_RATE_LIMITED",
                message:   "The AI quota has been reached for now.",
                hint:      "Wait a moment and try again. Stored questions for popular chapters are always available instantly."
            )
        }
        if lower.contains("timeout") || lower.contains("timed out") || lower.contains("deadline") {
            return QuizAPIError(
                errorCode: "AI_TIMEOUT",
                message:   "AI generation timed out on the server.",
                hint:      "Try again — it usually succeeds on the second attempt."
            )
        }
        if lower.contains("api key") || lower.contains("not configured") || lower.contains("unauthorized") {
            return QuizAPIError(
                errorCode: "AI_NOT_CONFIGURED",
                message:   "AI generation is not configured on the server.",
                hint:      nil
            )
        }
        if lower.contains("safety") || lower.contains("blocked") || lower.contains("harm") {
            return QuizAPIError(
                errorCode: "AI_BLOCKED",
                message:   "The AI safety filter blocked this request.",
                hint:      "Try a different chapter."
            )
        }
        if lower.contains("book") && lower.contains("not found") {
            return QuizAPIError(
                errorCode: "BOOK_NOT_FOUND",
                message:   "This book was not found in the quiz database.",
                hint:      nil
            )
        }
        // Unknown string — fall through to HTTP-status mapping
        return fallbackError(forStatus: httpStatus)
    }

    // MARK: - HTTP status → friendly error (for proxy / infra-level responses)

    private static func fallbackError(forStatus status: Int) -> QuizAPIError {
        switch status {
        case 429:
            return QuizAPIError(
                errorCode: "GEMINI_RATE_LIMITED",
                message:   "AI generation is temporarily rate-limited.",
                hint:      "Wait about 60 seconds and try again."
            )
        case 500:
            return QuizAPIError(
                errorCode: "SERVER_ERROR",
                message:   "The server encountered an internal error.",
                hint:      "This is usually temporary — try again in a moment."
            )
        case 502:
            return QuizAPIError(
                errorCode: "GEMINI_NETWORK_ERROR",
                message:   "AI generation couldn't complete right now.",
                hint:      "This happens occasionally when the AI is busy. Tap Try Again — it usually works on the second attempt."
            )
        case 503:
            return QuizAPIError(
                errorCode: "SERVER_UNAVAILABLE",
                message:   "The server is temporarily unavailable.",
                hint:      "It may be restarting. Try again in a few seconds."
            )
        case 504:
            return QuizAPIError(
                errorCode: "GEMINI_TIMEOUT",
                message:   "AI generation timed out on the server.",
                hint:      "Try again — shorter chapters tend to generate faster."
            )
        default:
            return QuizAPIError(
                errorCode: "HTTP_\(status)",
                message:   "Something went wrong on the server (HTTP \(status)).",
                hint:      "Try again in a moment."
            )
        }
    }

    // MARK: - Fetch translations of specific questions by group_id

    /// Given group_ids from already-loaded questions, fetches the same questions
    /// in a different language. Used by the language switcher in VerseQuizSheet.
    func questionsByGroups(groupIds: [String], lang: String) async -> [QuizQuestion] {
        guard !groupIds.isEmpty else { return [] }
        let ids = groupIds.joined(separator: ",")
        guard let url = URL(string: "\(baseURL)/by-groups?group_ids=\(ids)&lang=\(lang)") else { return [] }
        return await _fetch(path: url.absoluteString) ?? []
    }

    // MARK: - Generate for ALL languages (EN + AM + OR + TI in one call)

    /// Calls `POST /quiz/generate-all-languages` so every language version is
    /// cached server-side after the first quiz request for a chapter.
    /// Returns a dict of language → count, e.g. {"niv":5,"am":5,"or":4,"ti":5}.
    func generateAllLanguages(
        book:    String,
        chapter: Int,
        count:   Int = 5
    ) async -> [String: Int] {
        guard let url = URL(string: "\(baseURL)/generate-all-languages") else { return [:] }

        var request        = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180   // translation takes longer

        struct Body: Encodable { let book: String; let chapter: Int; let count: Int; let save: Bool }
        request.httpBody = try? JSONEncoder().encode(Body(book: book, chapter: chapter, count: count, save: true))

        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [:] }
            struct Resp: Decodable { let generated_per_language: [String: Int] }
            return (try? JSONDecoder().decode(Resp.self, from: data))?.generated_per_language ?? [:]
        } catch { return [:] }
    }

    // MARK: - Submit answer

    func submitAnswer(questionId: Int, selected: String) async -> QuizAnswerResponse? {
        guard let url = URL(string: "\(baseURL)/answer") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(
            AnswerRequest(questionId: questionId, selected: selected)
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(QuizAnswerResponse.self, from: data)
        } catch { return nil }
    }
}

// MARK: - QuizAPIError convenience

extension QuizAPIError {
    /// Human-readable title.
    /// Handles both the new generic AI_* codes (Mistral) and legacy GEMINI_* codes.
    var friendlyTitle: String {
        switch errorCode {
        // New generic codes (Mistral)
        case "AI_RATE_LIMITED":         return "AI Rate Limited"
        case "AI_TIMEOUT":              return "AI Timed Out"
        case "AI_NOT_CONFIGURED":       return "Not Available"
        case "AI_NETWORK_ERROR":        return "Connection Error"
        case "AI_BLOCKED":              return "Content Filtered"
        case "AI_PARSE_ERROR":          return "Temporary Issue"
        case "AI_UNAUTHORIZED":         return "API Key Invalid"
        case "AI_SERVER_ERROR",
             "AI_UNAVAILABLE":          return "Server Issue"
        // Legacy Gemini codes (kept for backward compat with old API responses)
        case "GEMINI_RATE_LIMITED":     return "AI Rate Limited"
        case "GEMINI_TIMEOUT":          return "AI Timed Out"
        case "GEMINI_NOT_CONFIGURED":   return "Not Available"
        case "GEMINI_NETWORK_ERROR":    return "Connection Error"
        case "GEMINI_BLOCKED":          return "Content Filtered"
        case "GEMINI_PARSE_ERROR":      return "Temporary Issue"
        // Data errors
        case "NO_QUESTIONS_FOUND":      return "No Questions Yet"
        case "BOOK_NOT_FOUND":          return "Book Not Found"
        case "CHAPTER_OUT_OF_RANGE":    return "Invalid Chapter"
        default:                        return "Something Went Wrong"
        }
    }

    /// SF Symbol name that best represents the error.
    var iconName: String {
        switch errorCode {
        case "AI_RATE_LIMITED",
             "GEMINI_RATE_LIMITED":     return "clock.arrow.circlepath"
        case "AI_TIMEOUT",
             "GEMINI_TIMEOUT":          return "hourglass.tophalf.filled"
        case "AI_NOT_CONFIGURED",
             "GEMINI_NOT_CONFIGURED":   return "sparkles.slash"
        case "AI_BLOCKED",
             "GEMINI_BLOCKED":          return "hand.raised.fill"
        case "AI_UNAUTHORIZED":         return "key.slash"
        case "AI_NETWORK_ERROR",    "AI_PARSE_ERROR",
             "GEMINI_NETWORK_ERROR","GEMINI_PARSE_ERROR": return "wifi.exclamationmark"
        default:                        return "exclamationmark.circle"
        }
    }

    /// True when the user might succeed by retrying after a short wait.
    var isRetryable: Bool {
        switch errorCode {
        case "AI_RATE_LIMITED",  "AI_TIMEOUT",
             "AI_NETWORK_ERROR", "AI_PARSE_ERROR",
             "AI_SERVER_ERROR",  "AI_UNAVAILABLE",
             "GEMINI_RATE_LIMITED", "GEMINI_TIMEOUT",
             "GEMINI_NETWORK_ERROR","GEMINI_PARSE_ERROR": return true
        default: return false
        }
    }
}
