import SwiftUI
import SafariServices

struct TermsOfServiceView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: URL(string: "https://gorobale.tech/terms")!)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
