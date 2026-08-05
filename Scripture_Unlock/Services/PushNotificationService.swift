import Foundation
import Auth
import UserNotifications
import UIKit

// MARK: - PushNotificationService
//
// Handles APNs device token registration + storage in Supabase `device_tokens` table.
//
// Setup required (one-time, manual):
//   1. In Xcode target → Signing & Capabilities → add "Push Notifications"
//   2. In Apple Developer Portal → Certificates → create an APNs Auth Key (.p8)
//   3. In Supabase Dashboard → Settings → Edge Functions → add secrets:
//      APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY, APNS_BUNDLE_ID
//
// The `send-push` edge function (deployed separately) reads those secrets
// and delivers notifications via the APNs HTTP/2 API.

@Observable
final class PushNotificationService {
    static let shared = PushNotificationService()
    private init() {}

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var deviceToken: String? = nil

    // MARK: - Public

    /// Request permission then register with APNs.
    /// Call this at app launch after onboarding completes.
    func requestAndRegister() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        if settings.authorizationStatus == .notDetermined {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            await MainActor.run { authorizationStatus = granted ? .authorized : .denied }
            if granted { registerWithAPNs() }
        } else {
            await MainActor.run { authorizationStatus = settings.authorizationStatus }
            if settings.authorizationStatus == .authorized { registerWithAPNs() }
        }
    }

    /// Call from AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)
    func didRegisterToken(_ token: Data) {
        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
        deviceToken = tokenString
        Task { await storeToken(tokenString) }
    }

    /// Trigger a push notification for a specific user (calls the send-push edge function).
    func sendPush(to userId: String, title: String, body: String, data: [String: String] = [:]) async {
        guard let session = try? await SupabaseService.shared.currentSession() else { return }
        let host    = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_HOST") as? String ?? ""
        let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
        guard let url = URL(string: "https://\(host)/functions/v1/send-push") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "userId": userId, "title": title, "body": body, "data": data
        ])
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Private

    private func registerWithAPNs() {
        Task { @MainActor in
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    private func storeToken(_ token: String) async {
        guard SupabaseService.shared.isSignedIn,
              let session = try? await SupabaseService.shared.currentSession() else { return }
        let host    = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_HOST") as? String ?? ""
        let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
        guard let url = URL(string: "https://\(host)/rest/v1/device_tokens"),
              let body = try? JSONSerialization.data(withJSONObject: [
                "user_id": session.user.id.uuidString,
                "token": token, "platform": "ios",
                "updated_at": ISO8601DateFormatter().string(from: Date())
              ]) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"; req.httpBody = body
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        _ = try? await URLSession.shared.data(for: req)
    }
}
