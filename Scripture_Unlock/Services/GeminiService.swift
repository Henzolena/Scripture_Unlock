import Foundation

// MARK: - GeminiService
//
// Thin HTTP wrapper around the Gemini generateContent API.
//
// Key is read from Bundle.main (injected via Secrets.xcconfig → Info.plist).
// For production: replace with a Supabase Edge Function proxy so the key
// never ships inside the app binary.
//
// Model waterfall (tried in order until one succeeds):
//   1. gemini-3.1-flash-lite   — primary, reliable free tier
//   2. gemini-flash-lite-latest — fallback if primary is overloaded
//
// Retry: up to 3 attempts per model with exponential back-off on 429/503.

final class GeminiService {

    static let shared = GeminiService()
    private init() {}

    // MARK: - Config

    var apiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String ?? ""
    }

    /// Models tried in order. If the first returns 429 or 503 after retries,
    /// the next model in the list is attempted.
    private let modelWaterfall = [
        "gemini-3.1-flash-lite",
        "gemini-flash-lite-latest",
    ]

    private let baseURL  = "https://generativelanguage.googleapis.com/v1beta/models"
    private let session  = URLSession.shared
    private let maxRetries = 3

    // MARK: - Errors

    enum GeminiError: LocalizedError {
        case missingAPIKey
        case allModelsExhausted
        case httpError(Int, String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Gemini API key not configured. Add GEMINI_API_KEY to Secrets.xcconfig."
            case .allModelsExhausted:
                return "All Gemini models returned rate-limit or server errors. Try again in a minute."
            case .httpError(let code, let body):
                return "Gemini HTTP \(code): \(body.prefix(120))"
            case .emptyResponse:
                return "Gemini returned an empty response."
            }
        }
    }

    // MARK: - Public API

    /// Send a prompt and receive a guaranteed-JSON string back.
    /// Tries each model in `modelWaterfall`; retries on 429/503 with back-off.
    func generate(prompt: String) async throws -> String {
        guard !apiKey.isEmpty else { throw GeminiError.missingAPIKey }

        var lastError: Error = GeminiError.allModelsExhausted

        for model in modelWaterfall {
            do {
                let result = try await generateWithRetry(prompt: prompt, model: model)
                return result
            } catch GeminiError.httpError(let code, _) where code == 429 || code == 503 {
                // Rate-limited or overloaded — try next model
                print("[GeminiService] \(model) returned \(code), trying next model…")
                lastError = GeminiError.allModelsExhausted
                continue
            } catch {
                // Any other error (400, parse failure, etc.) — surface immediately
                throw error
            }
        }

        throw lastError
    }

    // MARK: - Private: retry loop

    private func generateWithRetry(prompt: String, model: String) async throws -> String {
        var attempt = 0

        while attempt < maxRetries {
            attempt += 1
            do {
                return try await callAPI(prompt: prompt, model: model)
            } catch GeminiError.httpError(let code, _) where code == 429 || code == 503 {
                if attempt < maxRetries {
                    let delay = Double(1 << attempt)   // 2s, 4s, 8s
                    print("[GeminiService] \(model) attempt \(attempt) → \(code), retrying in \(Int(delay))s…")
                    try await Task.sleep(for: .seconds(delay))
                } else {
                    throw GeminiError.httpError(code, "Rate limit after \(maxRetries) attempts on \(model)")
                }
            }
        }

        throw GeminiError.allModelsExhausted
    }

    // MARK: - Private: single API call

    private func callAPI(prompt: String, model: String) async throws -> String {
        let urlString = "\(baseURL)/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiError.httpError(0, "Invalid URL for model \(model)")
        }

        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "temperature": 0.7,
                "maxOutputTokens": 8192,
            ]
        ]

        var request        = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody   = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.httpError(0, "No HTTP response")
        }

        guard http.statusCode == 200 else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw GeminiError.httpError(http.statusCode, bodyText)
        }

        guard let envelope  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = envelope["candidates"] as? [[String: Any]],
              let first      = candidates.first,
              let content    = first["content"] as? [String: Any],
              let parts      = content["parts"] as? [[String: Any]],
              let text       = parts.first?["text"] as? String,
              !text.isEmpty
        else {
            throw GeminiError.emptyResponse
        }

        return text
    }
}
