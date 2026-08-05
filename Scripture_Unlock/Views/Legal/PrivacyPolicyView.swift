import SwiftUI
import SafariServices

struct PrivacyPolicyView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: URL(string: "https://gorobale.tech/privacy")!)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
