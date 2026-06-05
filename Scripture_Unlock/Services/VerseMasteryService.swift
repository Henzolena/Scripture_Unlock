import Foundation
import Auth

// MARK: - Models

struct PackMasteryStats {
    let masteredCount:    Int   // correct_count ≥ 6  (mastery level ≥ 3)
    let inProgressCount:  Int   // correct_count 1–5  (mastery level 1–2)
    let totalVerses:      Int   // from VersePack catalog

    var learnedCount: Int { masteredCount }
    var progressFraction: Double {
        guard totalVerses > 0 else { return 0 }
        return Double(masteredCount) / Double(totalVerses)
    }
    var remainingCount: Int { totalVerses - masteredCount }
}

struct MasteryEntry: Codable {
    var correctCount:  Int
    var attemptCount:  Int
    var lastPracticed: String   // ISO date "2026-06-04"
}

// MARK: - Service

/// Manages per-verse mastery state for the Verse Packs feature.
///
/// Persistence strategy:
///   • Always written to UserDefaults (works offline / without sign-in)
///   • Synced to Supabase `verse_mastery` table when the user is signed in
///   • On sign-in / app launch, cloud data is merged (higher correct_count wins)
@Observable
final class VerseMasteryService {

    static let shared = VerseMasteryService()

    // MARK: - State

    /// In-memory cache loaded from UserDefaults.
    /// Key: "\(packId)|\(verseRef)" e.g. "psalms|Psalm 23:1"
    private(set) var entries: [String: MasteryEntry] = [:]
    private let udKey = "verse_mastery_v1"

    // MARK: - Init

    private init() { loadLocal() }

    // MARK: - Public — mastery level

    func masteryLevel(packId: String, verseRef: String) -> Int {
        let c = entries[key(packId, verseRef)]?.correctCount ?? 0
        switch c {
        case 0:      return 0
        case 1...2:  return 1
        case 3...5:  return 2
        case 6...9:  return 3
        case 10...14: return 4
        default:     return 5
        }
    }

    // MARK: - Public — today's practice question

    /// Returns the best question to practice today for a pack:
    /// lowest mastery first, never already practiced today.
    func todaysPracticeQuestion(packId: String,
                                difficulty: Difficulty = .regular) -> TriviaQuestion? {
        let qs = QuestionGeneratorAgent.shared.questions(forPack: packId,
                                                         difficulty: difficulty)
        guard !qs.isEmpty else { return nil }

        let today = todayStr()
        let notDoneToday = qs.filter { q in
            entries[key(packId, q.verseRef)]?.lastPracticed != today
        }
        // Sort ascending by mastery — lowest = most in need of practice
        return (notDoneToday.isEmpty ? qs : notDoneToday)
            .min { masteryLevel(packId: packId, verseRef: $0.verseRef)
                 < masteryLevel(packId: packId, verseRef: $1.verseRef) }
    }

    func isPracticedToday(packId: String, verseRef: String) -> Bool {
        entries[key(packId, verseRef)]?.lastPracticed == todayStr()
    }

    // MARK: - Public — record a practice result

    func recordPractice(packId: String, verseRef: String, correct: Bool) async {
        let k = key(packId, verseRef)
        var e = entries[k] ?? MasteryEntry(correctCount: 0, attemptCount: 0, lastPracticed: "")
        e.correctCount  += correct ? 1 : 0
        e.attemptCount  += 1
        e.lastPracticed  = todayStr()
        entries[k] = e
        saveLocal()

        if SupabaseService.shared.isSignedIn {
            await pushToSupabase(packId: packId, verseRef: verseRef, entry: e)
        }
    }

    // MARK: - Public — pack stats for the progress bar

    func stats(for packId: String) -> PackMasteryStats {
        let pack   = VersePack.find(packId)
        var mastered   = 0
        var inProgress = 0
        for (k, e) in entries where k.hasPrefix("\(packId)|") {
            let lvl = masteryFromCount(e.correctCount)
            if lvl >= 3 { mastered   += 1 }
            else if lvl >= 1 { inProgress += 1 }
        }
        return PackMasteryStats(
            masteredCount:   mastered,
            inProgressCount: inProgress,
            totalVerses:     pack.questionCount
        )
    }

    // MARK: - Cloud sync

    /// Pull cloud mastery and merge (higher correct_count wins).
    func syncFromCloud(packId: String) async {
        guard SupabaseService.shared.isSignedIn,
              let rows = await fetchFromSupabase(packId: packId) else { return }

        for row in rows {
            let k = key(packId, row.verseRef)
            let local = entries[k]
            // Cloud wins only if it has seen more correct answers
            if (local?.correctCount ?? 0) < row.correctCount {
                entries[k] = MasteryEntry(
                    correctCount:  row.correctCount,
                    attemptCount:  row.attemptCount,
                    lastPracticed: row.lastPracticed
                )
            }
        }
        saveLocal()
    }

    // MARK: - Helpers

    private func key(_ packId: String, _ verseRef: String) -> String {
        "\(packId)|\(verseRef)"
    }

    private func todayStr() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }

    private func masteryFromCount(_ c: Int) -> Int {
        switch c {
        case 0: return 0; case 1...2: return 1; case 3...5: return 2
        case 6...9: return 3; case 10...14: return 4; default: return 5
        }
    }

    // MARK: - Local persistence

    private func loadLocal() {
        guard let data = UserDefaults.standard.data(forKey: udKey),
              let decoded = try? JSONDecoder().decode([String: MasteryEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func saveLocal() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: udKey)
    }

    // MARK: - Supabase REST helpers

    private var sbURL: String {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_HOST") as? String ?? ""
    }
    private var sbAnon: String {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
    }

    private struct RemoteMasteryRow: Decodable {
        let verseRef:      String
        let correctCount:  Int
        let attemptCount:  Int
        let lastPracticed: String
        enum CodingKeys: String, CodingKey {
            case verseRef      = "verse_ref"
            case correctCount  = "correct_count"
            case attemptCount  = "attempt_count"
            case lastPracticed = "last_practiced"
        }
    }

    private func fetchFromSupabase(packId: String) async -> [RemoteMasteryRow]? {
        guard !sbURL.isEmpty, !sbAnon.isEmpty,
              let session = try? await SupabaseService.shared.currentSession() else { return nil }
        var comps = URLComponents(string: "https://\(sbURL)/rest/v1/verse_mastery")!
        comps.queryItems = [
            URLQueryItem(name: "pack_id", value: "eq.\(packId)"),
            URLQueryItem(name: "select",  value: "verse_ref,correct_count,attempt_count,last_practiced"),
        ]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        req.setValue(sbAnon,                   forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json",       forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return try JSONDecoder().decode([RemoteMasteryRow].self, from: data)
        } catch { return nil }
    }

    private func pushToSupabase(packId: String, verseRef: String, entry: MasteryEntry) async {
        guard !sbURL.isEmpty, !sbAnon.isEmpty,
              let session = try? await SupabaseService.shared.currentSession() else { return }
        guard let url = URL(string: "https://\(sbURL)/rest/v1/verse_mastery") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(sbAnon,                   forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json",       forHTTPHeaderField: "Content-Type")
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        let body: [String: Any] = [
            "user_id":       session.user.id.uuidString,
            "pack_id":       packId,
            "verse_ref":     verseRef,
            "correct_count": entry.correctCount,
            "attempt_count": entry.attemptCount,
            "last_practiced": entry.lastPracticed,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }
}
