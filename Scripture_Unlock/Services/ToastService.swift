import Foundation
import UIKit

@Observable
final class ToastService {
    static let shared = ToastService()
    private init() {}

    struct Toast: Identifiable, Equatable {
        let id   = UUID()
        let message: String
        let icon:    String
        let style:   Style

        enum Style { case success, info, gold, warning }

        static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
    }

    private(set) var current: Toast? = nil

    // MARK: - Public API

    func show(
        _ message: String,
        icon: String = "checkmark.circle.fill",
        style: Toast.Style = .success,
        haptic: HapticKind = .success
    ) {
        fire(haptic)
        Task { @MainActor in
            current = Toast(message: message, icon: icon, style: style)
            try? await Task.sleep(for: .seconds(2.4))
            current = nil
        }
    }

    // Convenience overloads
    func bookmarked()        { show("Bookmarked",         icon: "bookmark.fill",          style: .gold,    haptic: .medium) }
    func unbookmarked()      { show("Bookmark removed",   icon: "bookmark.slash.fill",    style: .info,    haptic: .light)  }
    func noteSaved()         { show("Note saved",         icon: "pencil.line",            style: .success, haptic: .success)}
    func noteDeleted()       { show("Note deleted",       icon: "trash.fill",             style: .info,    haptic: .light)  }
    func verseCopied()       { show("Verse copied",       icon: "doc.on.doc.fill",        style: .info,    haptic: .light)  }
    func friendRequestSent() { show("Request sent",       icon: "person.badge.plus.fill", style: .success, haptic: .medium) }
    func friendAccepted()    { show("Friend added!",      icon: "person.2.fill",          style: .success, haptic: .success)}
    func friendDeclined()    { show("Request declined",   icon: "xmark.circle.fill",      style: .info,    haptic: .light)  }
    func roomCreated()       { show("Room created",       icon: "house.fill",             style: .success, haptic: .success)}
    func roomJoined()        { show("Joined room",        icon: "link.circle.fill",       style: .success, haptic: .medium) }
    func settingsSaved()     { show("Saved",              icon: "checkmark.circle.fill",  style: .success, haptic: .light)  }

    // MARK: - Haptics

    enum HapticKind { case light, medium, success, warning }

    func fire(_ kind: HapticKind) {
        switch kind {
        case .light:   UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:  UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }
}
