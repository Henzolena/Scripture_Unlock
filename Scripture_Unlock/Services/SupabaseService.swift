import Foundation
import Auth       // AuthClient, Session, KeychainLocalStorage — already linked in target
import PostgREST  // PostgrestClient — already linked in target
import AuthenticationServices
import SwiftData

// MARK: - SupabaseService
//
// Uses the official Supabase Swift SDK sub-modules (Auth + PostgREST, v2.x).
// The SDK handles:
//   • Keychain storage for access/refresh tokens (KeychainLocalStorage)
//   • Silent token refresh before expiry (autoRefreshToken: true by default)
//   • Auth state observation via authStateChanges
//
// Public interface for SwiftUI views:
//   isSignedIn, isSyncing, userEmail, syncStatus
//   handleSignInResult(_:)   call from SignInWithAppleButton onCompletion
//   signOut()
//   syncFromCloud(context:)  pull cloud → local SwiftData (profile, streaks, alarms)
//   upsertProfile(_:)        push local profile change → cloud
//   upsertStreakEntry(_:)    push local streak entry → cloud
//   upsertAlarm(_:)          push alarm create/edit/toggle → cloud
//   deleteAlarm(id:)         remove alarm from cloud on delete

@Observable
final class SupabaseService {

    static let shared = SupabaseService()

    // MARK: - Observable state

    private(set) var isSignedIn: Bool   = false
    private(set) var isSyncing:  Bool   = false
    private(set) var userEmail:  String = ""
    private(set) var syncStatus: String = ""

    // MARK: - SDK

    private let auth: AuthClient
    private let host: String
    private let anonKey: String

    private init() {
        host    = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_HOST")     as? String ?? ""
        anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""

        // AuthClient stores the session in the iOS Keychain automatically.
        // It also handles silent token refresh so we never need to call refresh manually.
        auth = AuthClient(configuration: .init(
            url:                              URL(string: "https://\(host)/auth/v1")!,
            headers:                          ["apikey": anonKey],
            localStorage:                     KeychainLocalStorage(),
            logger:                           nil,
            emitLocalSessionAsInitialSession: true   // always emit local session on startup
        ))

        // Restore any persisted session synchronously so isSignedIn is correct
        // before the first SwiftUI render.
        if let session = auth.currentSession {
            isSignedIn = true
            userEmail  = session.user.email ?? ""
        }

        // Observe future auth events (sign-in, token refresh, sign-out)
        Task { await observeAuthState() }
    }

    // MARK: - Auth state observation

    private func observeAuthState() async {
        for await (event, session) in auth.authStateChanges {
            await MainActor.run {
                switch event {
                case .signedIn, .tokenRefreshed, .userUpdated:
                    isSignedIn = true
                    userEmail  = session?.user.email ?? userEmail
                case .signedOut:
                    isSignedIn = false
                    userEmail  = ""
                    syncStatus = ""
                default:
                    break
                }
            }
        }
    }

    // MARK: - Sign in with Apple

    /// Call from `SignInWithAppleButton`'s `onCompletion` closure.
    func handleSignInResult(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            print("[Auth] Apple sign-in cancelled: \(error.localizedDescription)")

        case .success(let authorization):
            guard let cred      = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken,
                  let idToken   = String(data: tokenData, encoding: .utf8) else {
                await MainActor.run { syncStatus = "⚠️ Apple did not provide an identity token" }
                return
            }

            await MainActor.run { syncStatus = "Connecting…" }

            do {
                let session = try await auth.signInWithIdToken(
                    credentials: .init(provider: .apple, idToken: idToken)
                )
                await MainActor.run {
                    isSignedIn = true
                    userEmail  = session.user.email ?? ""
                    syncStatus = "✅ Signed in"
                }
            } catch {
                await MainActor.run {
                    syncStatus = "⚠️ Could not sign in: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Sign out

    func signOut() async {
        try? await auth.signOut()
        // authStateChanges observer handles setting isSignedIn = false
    }

    // MARK: - Two-way sync (cloud → local SwiftData)

    @MainActor
    func syncFromCloud(context: ModelContext) async {
        guard isSignedIn else { return }
        guard !isSyncing else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let session = try await auth.session          // throws if no valid session
            let uid     = session.user.id.uuidString
            let db      = makeDB(token: session.accessToken)

            // Fetch profile, streaks, and alarms in parallel
            async let profileFetch: [RemoteProfile]    = db.from("profiles")
                .select()
                .eq("id", value: uid)
                .execute()
                .value
            async let streakFetch: [RemoteStreakEntry] = db.from("streak_entries")
                .select()
                .eq("user_id", value: uid)
                .order("date", ascending: false)
                .execute()
                .value
            async let alarmFetch: [RemoteAlarm]        = db.from("alarms")
                .select()
                .eq("user_id", value: uid)
                .execute()
                .value

            let (profiles, streaks, remoteAlarms) = try await (profileFetch, streakFetch, alarmFetch)

            // Apply remote profile to local SwiftData.
            // If the remote row has no name it was just auto-created by the
            // handle_new_user trigger (first sign-in after onboarding). In that
            // case push local settings up so the DB gets the real values.
            // Otherwise the cloud is authoritative and we overwrite locally.
            if let remote = profiles.first,
               let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first {
                if remote.name.isEmpty {
                    await upsertProfile(profile)
                } else {
                    profile.name                        = remote.name
                    profile.activePackId               = remote.activePackId
                    profile.questionCount              = remote.questionCount
                    profile.snoozeTaxEnabled           = remote.snoozeTax
                    profile.sabbathModeEnabled         = remote.sabbathMode
                    profile.appearanceRaw              = remote.appearance
                    profile.parallelLanguage           = remote.parallelLanguage
                    profile.accountabilityPartnerEmail = remote.accountabilityPartnerEmail
                }
            }

            // Replace local streaks with cloud (cloud is authoritative when signed in)
            let existing = (try? context.fetch(FetchDescriptor<StreakEntry>())) ?? []
            existing.forEach { context.delete($0) }

            let dayFmt = DateFormatter(); dayFmt.dateFormat = "yyyy-MM-dd"
            let isoFmt = ISO8601DateFormatter()
            for remote in streaks {
                guard let date = dayFmt.date(from: remote.date) else { continue }
                let entry = StreakEntry(date: Calendar.current.startOfDay(for: date))
                entry.questionsAnswered = remote.questionsAnswered
                entry.questionsCorrect  = remote.questionsCorrect
                entry.snoozeCount       = remote.snoozeCount
                entry.dismissedAt       = remote.dismissedAt.flatMap { isoFmt.date(from: $0) }
                context.insert(entry)
            }

            // Merge cloud alarms into local SwiftData (cloud is authoritative)
            let localAlarms  = (try? context.fetch(FetchDescriptor<Alarm>())) ?? []
            let remoteIdSet  = Set(remoteAlarms.compactMap { UUID(uuidString: $0.id) })

            // Cancel + remove alarms that were deleted on another device
            for local in localAlarms where !remoteIdSet.contains(local.id) {
                await AlarmService.shared.cancel(local)
                context.delete(local)
            }

            // Insert or update alarms from cloud
            for remote in remoteAlarms {
                guard let remoteId = UUID(uuidString: remote.id) else { continue }
                if let existing = localAlarms.first(where: { $0.id == remoteId }) {
                    existing.label          = remote.label
                    existing.hour           = remote.hour
                    existing.minute         = remote.minute
                    existing.isAM           = remote.isAM
                    existing.isEnabled      = remote.isEnabled
                    existing.repeatDays     = remote.repeatDays
                    existing.packId         = remote.packId
                    existing.translationRaw = remote.translationRaw
                    existing.difficultyRaw  = remote.difficultyRaw
                    existing.questionCount  = remote.questionCount
                    existing.toneIdentifier = remote.toneIdentifier
                } else {
                    let alarm = Alarm()
                    alarm.id             = remoteId
                    alarm.label          = remote.label
                    alarm.hour           = remote.hour
                    alarm.minute         = remote.minute
                    alarm.isAM           = remote.isAM
                    alarm.isEnabled      = remote.isEnabled
                    alarm.repeatDays     = remote.repeatDays
                    alarm.packId         = remote.packId
                    alarm.translationRaw = remote.translationRaw
                    alarm.difficultyRaw  = remote.difficultyRaw
                    alarm.questionCount  = remote.questionCount
                    alarm.toneIdentifier = remote.toneIdentifier
                    alarm.createdAt      = isoFmt.date(from: remote.createdAt) ?? Date()
                    context.insert(alarm)
                }
            }

            // Reschedule all enabled alarms so they fire on this device
            let allAlarms = (try? context.fetch(FetchDescriptor<Alarm>())) ?? []
            await AlarmService.shared.rescheduleAll(allAlarms)

            syncStatus = "✅ Synced · \(Date().formatted(.dateTime.hour().minute()))"

        } catch {
            // Session missing = signed out elsewhere; all other errors = transient
            syncStatus = "⚠️ Sync failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Push to cloud

    func upsertProfile(_ profile: UserProfile) async {
        guard isSignedIn else { return }
        guard let session = try? await auth.session else { return }
        let payload = ProfilePayload(
            id:                           session.user.id.uuidString,
            name:                         profile.name,
            activePackId:                 profile.activePackId,
            questionCount:                profile.questionCount,
            snoozeTax:                    profile.snoozeTaxEnabled,
            sabbathMode:                  profile.sabbathModeEnabled,
            appearance:                   profile.appearanceRaw,
            parallelLanguage:             profile.parallelLanguage,
            accountabilityPartnerEmail:   profile.accountabilityPartnerEmail
        )
        _ = try? await makeDB(token: session.accessToken).from("profiles").upsert(payload).execute()
    }

    func upsertStreakEntry(_ entry: StreakEntry) async {
        guard isSignedIn else { return }
        guard let session = try? await auth.session else { return }
        let dayFmt = DateFormatter(); dayFmt.dateFormat = "yyyy-MM-dd"
        let payload = StreakPayload(
            userId:            session.user.id.uuidString,
            date:              dayFmt.string(from: entry.date),
            questionsAnswered: entry.questionsAnswered,
            questionsCorrect:  entry.questionsCorrect,
            snoozeCount:       entry.snoozeCount,
            dismissedAt:       entry.dismissedAt.map { ISO8601DateFormatter().string(from: $0) }
        )
        _ = try? await makeDB(token: session.accessToken).from("streak_entries").upsert(payload).execute()
    }

    func upsertAlarm(_ alarm: Alarm) async {
        guard isSignedIn else { return }
        guard let session = try? await auth.session else { return }
        let isoFmt = ISO8601DateFormatter()
        let payload = AlarmPayload(
            id:             alarm.id.uuidString,
            userId:         session.user.id.uuidString,
            label:          alarm.label,
            hour:           alarm.hour,
            minute:         alarm.minute,
            isAM:           alarm.isAM,
            isEnabled:      alarm.isEnabled,
            repeatDays:     alarm.repeatDays,
            packId:         alarm.packId,
            translationRaw: alarm.translationRaw,
            difficultyRaw:  alarm.difficultyRaw,
            questionCount:  alarm.questionCount,
            toneIdentifier: alarm.toneIdentifier,
            createdAt:      isoFmt.string(from: alarm.createdAt)
        )
        _ = try? await makeDB(token: session.accessToken).from("alarms").upsert(payload).execute()
    }

    func deleteAlarm(id: UUID) async {
        guard isSignedIn else { return }
        guard let session = try? await auth.session else { return }
        _ = try? await makeDB(token: session.accessToken)
            .from("alarms")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Helpers

    /// Creates an authenticated PostgREST client for a single request batch.
    /// A fresh client is created each time to guarantee the latest access token is used.
    private func makeDB(token: String) -> PostgrestClient {
        PostgrestClient(
            url:     URL(string: "https://\(host)/rest/v1")!,
            schema:  "public",
            headers: ["apikey": anonKey, "Authorization": "Bearer \(token)"],
            logger:  nil
        )
    }
}

// MARK: - Remote DTOs (Decodable)

private struct RemoteProfile: Decodable, Sendable {
    let name:                         String
    let activePackId:                 String
    let questionCount:                Int
    let snoozeTax:                    Bool
    let sabbathMode:                  Bool
    let appearance:                   String
    let parallelLanguage:             String
    let accountabilityPartnerEmail:   String

    enum CodingKeys: String, CodingKey {
        case name, appearance
        case activePackId                = "active_pack_id"
        case questionCount               = "question_count"
        case snoozeTax                   = "snooze_tax"
        case sabbathMode                 = "sabbath_mode"
        case parallelLanguage            = "parallel_language"
        case accountabilityPartnerEmail  = "accountability_partner_email"
    }
}

private struct RemoteStreakEntry: Decodable, Sendable {
    let date:              String
    let questionsAnswered: Int
    let questionsCorrect:  Int
    let snoozeCount:       Int
    let dismissedAt:       String?

    enum CodingKeys: String, CodingKey {
        case date
        case questionsAnswered = "questions_answered"
        case questionsCorrect  = "questions_correct"
        case snoozeCount       = "snooze_count"
        case dismissedAt       = "dismissed_at"
    }
}

private struct RemoteAlarm: Decodable, Sendable {
    let id:             String
    let label:          String
    let hour:           Int
    let minute:         Int
    let isAM:           Bool
    let isEnabled:      Bool
    let repeatDays:     [Int]
    let packId:         String
    let translationRaw: String
    let difficultyRaw:  String
    let questionCount:  Int
    let toneIdentifier: String
    let createdAt:      String

    enum CodingKeys: String, CodingKey {
        case id, label, hour, minute
        case isAM           = "is_am"
        case isEnabled      = "is_enabled"
        case repeatDays     = "repeat_days"
        case packId         = "pack_id"
        case translationRaw = "translation_raw"
        case difficultyRaw  = "difficulty_raw"
        case questionCount  = "question_count"
        case toneIdentifier = "tone_identifier"
        case createdAt      = "created_at"
    }
}

// MARK: - Upsert payloads (Encodable)

private struct ProfilePayload: Encodable {
    let id:                           String
    let name:                         String
    let activePackId:                 String
    let questionCount:                Int
    let snoozeTax:                    Bool
    let sabbathMode:                  Bool
    let appearance:                   String
    let parallelLanguage:             String
    let accountabilityPartnerEmail:   String

    enum CodingKeys: String, CodingKey {
        case id, name, appearance
        case activePackId                = "active_pack_id"
        case questionCount               = "question_count"
        case snoozeTax                   = "snooze_tax"
        case sabbathMode                 = "sabbath_mode"
        case parallelLanguage            = "parallel_language"
        case accountabilityPartnerEmail  = "accountability_partner_email"
    }
}

private struct AlarmPayload: Encodable {
    let id:             String
    let userId:         String
    let label:          String
    let hour:           Int
    let minute:         Int
    let isAM:           Bool
    let isEnabled:      Bool
    let repeatDays:     [Int]
    let packId:         String
    let translationRaw: String
    let difficultyRaw:  String
    let questionCount:  Int
    let toneIdentifier: String
    let createdAt:      String

    enum CodingKeys: String, CodingKey {
        case id, label, hour, minute
        case userId         = "user_id"
        case isAM           = "is_am"
        case isEnabled      = "is_enabled"
        case repeatDays     = "repeat_days"
        case packId         = "pack_id"
        case translationRaw = "translation_raw"
        case difficultyRaw  = "difficulty_raw"
        case questionCount  = "question_count"
        case toneIdentifier = "tone_identifier"
        case createdAt      = "created_at"
    }
}

private struct StreakPayload: Encodable {
    let userId:            String
    let date:              String
    let questionsAnswered: Int
    let questionsCorrect:  Int
    let snoozeCount:       Int
    let dismissedAt:       String?

    enum CodingKeys: String, CodingKey {
        case date
        case userId            = "user_id"
        case questionsAnswered = "questions_answered"
        case questionsCorrect  = "questions_correct"
        case snoozeCount       = "snooze_count"
        case dismissedAt       = "dismissed_at"
    }
}
