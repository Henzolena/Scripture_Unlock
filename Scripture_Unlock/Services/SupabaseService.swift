import Foundation
import Auth       // AuthClient, Session, KeychainLocalStorage — already linked in target
import PostgREST  // PostgrestClient — already linked in target
import Storage
import AuthenticationServices
import SwiftData

enum EmailOTPVerificationResult: Equatable {
    case newUser
    case existingUser
}

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
    private static let supportedEmailOTPCodeLengths: Set<Int> = [6, 8]

    // MARK: - Observable state

    private(set) var isSignedIn: Bool   = false
    private(set) var isSyncing:  Bool   = false
    private(set) var userEmail:  String = ""
    private(set) var syncStatus: String = ""

    // MARK: - SDK

    private let auth: AuthClient
    private let host: String
    private let anonKey: String
    private let avatarBucket = "profile-avatars"

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

    // MARK: - Email OTP sign in

    func sendEmailOTP(to email: String) async throws {
        let normalizedEmail = Self.normalizedEmail(email)
        guard Self.isValidEmail(normalizedEmail) else {
            throw SupabaseAuthFlowError.invalidEmail
        }

        await MainActor.run {
            syncStatus = "Sending sign-in code..."
        }

        do {
            try await auth.signInWithOTP(
                email: normalizedEmail,
                shouldCreateUser: true
            )
            await MainActor.run {
                userEmail = normalizedEmail
                syncStatus = "Code sent to \(normalizedEmail)"
            }
        } catch {
            await MainActor.run {
                syncStatus = "Could not send code: \(error.localizedDescription)"
            }
            throw error
        }
    }

    @discardableResult
    func verifyEmailOTP(email: String, token: String) async throws -> EmailOTPVerificationResult {
        let normalizedEmail = Self.normalizedEmail(email)
        let normalizedToken = token.filter(\.isNumber)

        guard Self.isValidEmail(normalizedEmail) else {
            throw SupabaseAuthFlowError.invalidEmail
        }
        guard Self.supportedEmailOTPCodeLengths.contains(normalizedToken.count) else {
            throw SupabaseAuthFlowError.invalidCode
        }

        await MainActor.run {
            syncStatus = "Verifying code..."
        }

        do {
            let response = try await verifyEmailOTPWithSupportedTypes(
                email: normalizedEmail,
                token: normalizedToken
            )

            guard let session = response.session else {
                throw SupabaseAuthFlowError.missingSession
            }

            let result: EmailOTPVerificationResult = Self.isLikelyNewUser(response.user) ? .newUser : .existingUser

            await MainActor.run {
                isSignedIn = true
                userEmail = session.user.email ?? normalizedEmail
                syncStatus = result == .newUser
                    ? "Welcome to Scripture Unlock. Your account is ready."
                    : "Signed in. Your progress will sync shortly."
            }

            return result
        } catch {
            await MainActor.run {
                syncStatus = "Could not verify code: \(error.localizedDescription)"
            }
            throw error
        }
    }

    // MARK: - Sign out

    func signOut() async {
        try? await auth.signOut()
        // authStateChanges observer handles setting isSignedIn = false
    }

    /// Exposes the current auth session so other services (e.g. VerseMasteryService)
    /// can make authenticated Supabase REST calls without duplicating auth logic.
    func currentSession() async throws -> Session {
        try await auth.session
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
                    profile.avatarPath                 = remote.avatarPath
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
            accountabilityPartnerEmail:   profile.accountabilityPartnerEmail,
            avatarPath:                    profile.avatarPath
        )
        _ = try? await makeDB(token: session.accessToken).from("profiles").upsert(payload).execute()
    }

    func profileAvatarPublicURL(path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !host.isEmpty else { return nil }
        return URL(string: "https://\(host)/storage/v1/object/public/\(avatarBucket)/\(trimmed)")
    }

    func uploadProfileAvatar(jpegData: Data, previousPath: String) async throws -> String {
        guard isSignedIn else { throw SupabaseProfileAvatarError.notSignedIn }
        let session = try await auth.session
        let uid = session.user.id.uuidString
        let path = "\(uid)/avatar-\(UUID().uuidString).jpg"

        do {
            try await makeStorage(token: session.accessToken)
                .from(avatarBucket)
                .upload(
                    path,
                    data: jpegData,
                    options: FileOptions(
                        cacheControl: "31536000",
                        contentType: "image/jpeg",
                        upsert: false
                    )
                )

            try await updateProfileAvatarPath(path, token: session.accessToken, userId: uid)

            if !previousPath.isEmpty, previousPath != path {
                _ = try? await makeStorage(token: session.accessToken)
                    .from(avatarBucket)
                    .remove(paths: [previousPath])
            }

            return path
        } catch {
            _ = try? await makeStorage(token: session.accessToken)
                .from(avatarBucket)
                .remove(paths: [path])
            throw error
        }
    }

    func removeProfileAvatar(path: String) async throws {
        guard isSignedIn else { throw SupabaseProfileAvatarError.notSignedIn }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let session = try await auth.session
        let uid = session.user.id.uuidString
        try await updateProfileAvatarPath("", token: session.accessToken, userId: uid)
        _ = try? await makeStorage(token: session.accessToken)
            .from(avatarBucket)
            .remove(paths: [trimmed])
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

    private func makeStorage(token: String) -> SupabaseStorageClient {
        SupabaseStorageClient(configuration: .init(
            url: URL(string: "https://\(host)/storage/v1")!,
            headers: ["apikey": anonKey, "Authorization": "Bearer \(token)"],
            logger: nil
        ))
    }

    private func updateProfileAvatarPath(_ path: String, token: String, userId: String) async throws {
        let payload = ProfileAvatarPayload(
            avatarPath: path,
            avatarUpdatedAt: ISO8601DateFormatter().string(from: Date())
        )
        _ = try await makeDB(token: token)
            .from("profiles")
            .update(payload)
            .eq("id", value: userId)
            .execute()
    }

    private func verifyEmailOTPWithSupportedTypes(email: String, token: String) async throws -> AuthResponse {
        var lastError: Error?
        for type in [EmailOTPType.signup, .magiclink, .email] {
            do {
                return try await auth.verifyOTP(
                    email: email,
                    token: token,
                    type: type
                )
            } catch {
                lastError = error
            }
        }
        throw lastError ?? SupabaseAuthFlowError.invalidCode
    }

    private static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isValidEmail(_ email: String) -> Bool {
        let parts = email.split(separator: "@")
        guard parts.count == 2,
              let local = parts.first,
              let domain = parts.last,
              !local.isEmpty,
              domain.contains("."),
              !domain.hasPrefix("."),
              !domain.hasSuffix(".") else {
            return false
        }
        return true
    }

    private static func isLikelyNewUser(_ user: User) -> Bool {
        let now = Date()
        let createdAge = abs(now.timeIntervalSince(user.createdAt))
        guard createdAge <= 10 * 60 else { return false }

        if let lastSignInAt = user.lastSignInAt {
            return abs(lastSignInAt.timeIntervalSince(user.createdAt)) <= 10 * 60
        }

        return true
    }
}

private enum SupabaseAuthFlowError: LocalizedError {
    case invalidEmail
    case invalidCode
    case missingSession

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Enter a valid email address."
        case .invalidCode:
            return "Enter the full code from your email."
        case .missingSession:
            return "The code was accepted, but no session was returned."
        }
    }
}

private enum SupabaseProfileAvatarError: LocalizedError {
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in before uploading a profile photo."
        }
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
    let avatarPath:                    String

    enum CodingKeys: String, CodingKey {
        case name, appearance
        case activePackId                = "active_pack_id"
        case questionCount               = "question_count"
        case snoozeTax                   = "snooze_tax"
        case sabbathMode                 = "sabbath_mode"
        case parallelLanguage            = "parallel_language"
        case accountabilityPartnerEmail  = "accountability_partner_email"
        case avatarPath                  = "avatar_path"
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
    let avatarPath:                    String

    enum CodingKeys: String, CodingKey {
        case id, name, appearance
        case activePackId                = "active_pack_id"
        case questionCount               = "question_count"
        case snoozeTax                   = "snooze_tax"
        case sabbathMode                 = "sabbath_mode"
        case parallelLanguage            = "parallel_language"
        case accountabilityPartnerEmail  = "accountability_partner_email"
        case avatarPath                  = "avatar_path"
    }
}

private struct ProfileAvatarPayload: Encodable {
    let avatarPath: String
    let avatarUpdatedAt: String

    enum CodingKeys: String, CodingKey {
        case avatarPath = "avatar_path"
        case avatarUpdatedAt = "avatar_updated_at"
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
