import Foundation

// MARK: - GeminiService
//
// Thin HTTP wrapper around the Gemini generateContent API.
//
// Key is read from Bundle.main (injected via Secrets.xcconfig → Info.plist).
// For production: replace with a Supabase Edge Function proxy so the key
// never ships inside the app binary.
//
// Usage:
//   let json = try await GeminiService.shared.generate(prompt: "...")
//   // json is guaranteed to be a valid JSON string (application/json mode)

final class GeminiService {

    static let shared = GeminiService()
    private init() {}

    // MARK: - Config

    var apiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String ?? ""
    }

    private let model   = "gemini-2.5-flash-lite"
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    private let session = URLSession.shared

    // MARK: - Errors

    enum GeminiError: LocalizedError {
        case missingAPIKey
        case httpError(Int)
        case emptyResponse
        case invalidJSON(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:        return "Gemini API key not configured in Secrets.xcconfig"
            case .httpError(let code):  return "Gemini API returned HTTP \(code)"
            case .emptyResponse:        return "Gemini returned an empty response"
            case .invalidJSON(let msg): return "Gemini response is not valid JSON: \(msg)"
            }
        }
    }

    // MARK: - Public API

    /// Send a prompt and receive a guaranteed-JSON string back.
    /// Uses `responseMimeType: "application/json"` so the model returns
    /// raw JSON without markdown fences.
    func generate(prompt: String) async throws -> String {
        guard !apiKey.isEmpty else { throw GeminiError.missingAPIKey }

        let urlString = "\(baseURL)/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiError.httpError(0)
        }

        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "temperature": 0.7,
                "maxOutputTokens": 8192
            ]
        ]

        var request        = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody   = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.httpError(0)
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[GeminiService] HTTP \(http.statusCode): \(body)")
            throw GeminiError.httpError(http.statusCode)
        }

        // Parse the Gemini envelope and extract the text content
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
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
