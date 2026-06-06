import SwiftUI

struct EmailOTPAuthView: View {
    let title: String
    let subtitle: String
    let showsContainer: Bool
    let successActionTitle: String?
    let onSuccess: (() -> Void)?

    @Environment(SupabaseService.self) private var supabase
    @State private var email = ""
    @State private var code = ""
    @State private var stage: Stage = .email
    @State private var statusMessage = ""
    @State private var isSending = false
    @State private var isVerifying = false
    @State private var resendCooldownSeconds = 0
    @State private var resendCooldownTask: Task<Void, Never>?
    @FocusState private var focusedField: Field?

    private static let supportedCodeLengths: Set<Int> = [6, 8]
    private static let maximumCodeLength = supportedCodeLengths.max() ?? 8

    private enum Stage: Equatable {
        case email
        case codeSent
        case verified(EmailOTPVerificationResult)
    }

    private enum Field {
        case email
        case code
    }

    var body: some View {
        Group {
            if showsContainer {
                content
                    .padding(16)
                    .background(DesignSystem.surface)
                    .cornerRadius(16)
                    .shadow(color: DesignSystem.shadow1, radius: 6, x: 0, y: 2)
            } else {
                content
            }
        }
        .onDisappear {
            resendCooldownTask?.cancel()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(DesignSystem.royalBlue)
                    .frame(width: 38, height: 38)
                    .background(DesignSystem.royalBlue.opacity(0.09))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DesignSystem.ink)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.slate600)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            switch stage {
            case .email:
                emailEntry
            case .codeSent:
                codeEntry
            case .verified(let result):
                verifiedContent(result)
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(statusColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var emailEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("you@example.com", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .email)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DesignSystem.ink)
                .padding(12)
                .background(DesignSystem.warmCream)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DesignSystem.slate400.opacity(0.22), lineWidth: 1)
                )

            AppActionButton(
                title: sendCodeButtonTitle,
                icon: "paperplane.fill",
                disabled: !canRequestCode,
                action: sendCode
            )
        }
        .onAppear {
            focusedField = .email
        }
    }

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter the code sent to \(normalizedEmail).")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignSystem.slate600)
                .fixedSize(horizontal: false, vertical: true)

            TextField("12345678", text: codeBinding)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .focused($focusedField, equals: .code)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(DesignSystem.ink)
                .padding(12)
                .background(DesignSystem.warmCream)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DesignSystem.royalBlue.opacity(0.22), lineWidth: 1)
                )

            AppActionButton(
                title: isVerifying ? "Verifying..." : "Verify and continue",
                icon: "checkmark.seal.fill",
                disabled: !isValidCodeLength(code.count) || isVerifying,
                action: verifyCode
            )

            Button {
                sendCode()
            } label: {
                Text(resendCodeButtonTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DesignSystem.royalBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .disabled(isSending || resendCooldownSeconds > 0)
        }
        .onAppear {
            focusedField = .code
        }
    }

    private func verifiedContent(_ result: EmailOTPVerificationResult) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(result == .newUser ? "Welcome to Scripture Unlock" : "Signed in")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DesignSystem.ink)
                    Text(result == .newUser
                         ? "Your account is ready. Your progress can now sync across devices."
                         : "Your saved progress will sync on this device.")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.slate600)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DesignSystem.bethanyGreen)
            }

            if let successActionTitle {
                AppActionButton(
                    title: successActionTitle,
                    icon: "arrow.right",
                    disabled: false,
                    action: { onSuccess?() }
                )
            }
        }
        .padding(12)
        .background(DesignSystem.bethanyGreen.opacity(0.08))
        .cornerRadius(13)
    }

    private var codeBinding: Binding<String> {
        Binding(
            get: { code },
            set: { code = String($0.filter(\.isNumber).prefix(Self.maximumCodeLength)) }
        )
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var canSendCode: Bool {
        let parts = normalizedEmail.split(separator: "@")
        return parts.count == 2 && (parts.last?.contains(".") == true)
    }

    private var canRequestCode: Bool {
        canSendCode && !isSending && resendCooldownSeconds == 0
    }

    private var sendCodeButtonTitle: String {
        if isSending { return "Sending..." }
        if resendCooldownSeconds > 0 { return "Try again in \(resendCooldownSeconds)s" }
        return "Send code"
    }

    private var resendCodeButtonTitle: String {
        if isSending { return "Sending new code..." }
        if resendCooldownSeconds > 0 { return "Send a new code in \(resendCooldownSeconds)s" }
        return "Send a new code"
    }

    private var statusColor: Color {
        if statusMessage.localizedCaseInsensitiveContains("could not")
            || statusMessage.localizedCaseInsensitiveContains("enter")
            || statusMessage.localizedCaseInsensitiveContains("rate limit")
            || statusMessage.localizedCaseInsensitiveContains("too many") {
            return DesignSystem.danger
        }
        return DesignSystem.slate600
    }

    private func isValidCodeLength(_ length: Int) -> Bool {
        Self.supportedCodeLengths.contains(length)
    }

    private func sendCode() {
        let targetEmail = normalizedEmail
        guard canSendCode else {
            statusMessage = "Enter a valid email address."
            return
        }
        guard resendCooldownSeconds == 0 else {
            return
        }

        isSending = true
        statusMessage = ""
        Task {
            do {
                try await supabase.sendEmailOTP(to: targetEmail)
                await MainActor.run {
                    email = targetEmail
                    code = ""
                    stage = .codeSent
                    statusMessage = "Check your inbox for the Scripture Unlock code."
                    isSending = false
                    focusedField = .code
                    startResendCooldown(seconds: 30)
                }
            } catch {
                await MainActor.run {
                    if isRateLimitError(error) {
                        stage = .codeSent
                        focusedField = .code
                        statusMessage = "A code was already sent recently. Use the latest code, or try again shortly."
                        startResendCooldown(seconds: 60)
                    } else {
                        statusMessage = error.localizedDescription
                    }
                    isSending = false
                }
            }
        }
    }

    private func verifyCode() {
        let targetEmail = normalizedEmail
        let token = code
        guard isValidCodeLength(token.count) else {
            statusMessage = "Enter the full code from your email."
            return
        }

        isVerifying = true
        statusMessage = ""
        Task {
            do {
                let result = try await supabase.verifyEmailOTP(email: targetEmail, token: token)
                await MainActor.run {
                    stage = .verified(result)
                    statusMessage = ""
                    isVerifying = false
                    focusedField = nil
                }
            } catch {
                await MainActor.run {
                    statusMessage = error.localizedDescription
                    isVerifying = false
                }
            }
        }
    }

    private func startResendCooldown(seconds: Int) {
        resendCooldownTask?.cancel()
        resendCooldownSeconds = seconds
        resendCooldownTask = Task {
            for remaining in stride(from: seconds - 1, through: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    resendCooldownSeconds = remaining
                }
            }
        }
    }

    private func isRateLimitError(_ error: Error) -> Bool {
        let description = error.localizedDescription.lowercased()
        return description.contains("rate limit")
            || description.contains("too many requests")
            || description.contains("429")
            || description.contains("over_email_send_rate_limit")
    }
}
