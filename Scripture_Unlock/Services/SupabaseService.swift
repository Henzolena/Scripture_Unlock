import Foundation

// MARK: - SupabaseService
// Requires the supabase-swift package:
//   File → Add Package Dependencies
//   URL: https://github.com/supabase-community/supabase-swift
//   Version: from 2.0.0
//
// After adding the package, uncomment the import below and the full implementation.
// Until then, this stub compiles without the dependency so the rest of the app builds.

// import Supabase

/// Thin wrapper around Supabase for user profile, streak, and
/// accountability-partner sync. All writes are fire-and-forget;
/// the app works fully offline (SwiftData is the source of truth).
@Observable
final class SupabaseService {

    static let shared = SupabaseService()

    var isSignedIn: Bool = false
    var currentUserId: UUID?

    private init() {}

    // MARK: - Auth

    func signInWithApple(idToken: String, nonce: String) async throws {
        // TODO: Uncomment after adding the supabase-swift package
        // let session = try await client.auth.signInWithIdToken(
        //     credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        // )
        // isSignedIn = true
        // currentUserId = session.user.id
    }

    func signOut() async throws {
        // try await client.auth.signOut()
        isSignedIn = false
        currentUserId = nil
    }

    // MARK: - Profile sync

    func upsertProfile(_ profile: UserProfile) async {
        // TODO: Uncomment after adding the supabase-swift package
    }

    // MARK: - Streak sync

    func upsertStreakEntry(_ entry: StreakEntry) async {
        // TODO: Uncomment after adding the supabase-swift package
    }
}
