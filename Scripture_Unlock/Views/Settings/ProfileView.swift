import SwiftUI
import SwiftData
import AuthenticationServices
import PhotosUI
import UIKit

private enum ProfileAvatarProcessingError: LocalizedError {
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "The selected image could not be read."
        }
    }
}

private struct ProfileAvatarCropSource: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ProfileView: View {
    let profile: UserProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SupabaseService.self) private var supabase
    @Query(sort: \StreakEntry.date, order: .reverse) private var entries: [StreakEntry]

    @State private var editingName       = false
    @State private var draftName         = ""
    @State private var showSignOutConfirm = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var avatarCropSource: ProfileAvatarCropSource?
    @State private var isUploadingAvatar = false
    @State private var avatarStatus = ""
    @State private var showRemoveAvatarConfirm = false

    private var currentStreak: Int {
        var count = 0
        var d = Calendar.current.startOfDay(for: Date())
        while entries.contains(where: {
            Calendar.current.isDate($0.date, inSameDayAs: d) && $0.dismissedAt != nil
        }) {
            count += 1
            d = Calendar.current.date(byAdding: .day, value: -1, to: d)!
        }
        return count
    }

    private var totalAnswered: Int { entries.reduce(0) { $0 + $1.questionsAnswered } }

    private var accuracy: Double {
        let ans = entries.reduce(0) { $0 + $1.questionsAnswered }
        let cor = entries.reduce(0) { $0 + $1.questionsCorrect }
        return ans > 0 ? Double(cor) / Double(ans) : 0
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                actionRow
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                heroHeader
                statsRow
                    .padding(.horizontal, 20)
                syncSection
                    .padding(.horizontal, 20)
                Spacer(minLength: 40)
            }
        }
        .background(DesignSystem.warmCream.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: selectedPhotoItem) { _, item in
            prepareSelectedAvatar(item)
        }
        .sheet(item: $avatarCropSource) { source in
            ProfileAvatarCropperView(
                image: source.image,
                onCancel: {
                    avatarCropSource = nil
                    avatarStatus = ""
                },
                onCrop: { jpegData in
                    avatarCropSource = nil
                    uploadCroppedAvatar(jpegData)
                }
            )
        }
        .confirmationDialog("Remove profile photo?", isPresented: $showRemoveAvatarConfirm, titleVisibility: .visible) {
            Button("Remove photo", role: .destructive) {
                removeAvatar()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your profile will use initials until you upload another photo.")
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            AppToolbarIconButton(systemName: "chevron.left", style: .neutral) {
                dismiss()
            }
            .accessibilityLabel("Back")

            if supabase.isSignedIn {
                AppToolbarIconButton(
                    systemName: "arrow.clockwise",
                    disabled: supabase.isSyncing
                ) {
                    Task { await supabase.syncFromCloud(context: context) }
                }
                .accessibilityLabel("Sync")
            }

            Spacer()

            AppToolbarTextButton(title: editingName ? "Save" : "Edit") {
                if editingName {
                    profile.name = draftName.trimmingCharacters(in: .whitespaces)
                    Task { await supabase.upsertProfile(profile) }
                } else {
                    draftName = profile.name
                }
                editingName.toggle()
            }
            .accessibilityLabel(editingName ? "Save profile" : "Edit profile")
        }
    }

    // MARK: - Hero header

    private var heroHeader: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "0D1B3E"), Color(hex: "1E3A5F")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [DesignSystem.pastoralGold.opacity(0.18), .clear],
                    center: .topTrailing, startRadius: 0, endRadius: 260
                )
            }
            .frame(height: 108)
            .overlay(alignment: .bottom) {
                avatarCircle
            }

            Color.clear.frame(height: 38)

            if editingName {
                TextField("Your name", text: $draftName)
                    .font(.system(size: 22, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DesignSystem.ink)
                    .padding(.horizontal, 40)
            } else {
                Text(profile.name.isEmpty ? "Set your name" : profile.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(DesignSystem.ink)
            }

            syncBadge
                .padding(.top, 6)

            avatarActions
                .padding(.top, 10)

            if !avatarStatus.isEmpty {
                Text(avatarStatus)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(avatarStatus.localizedCaseInsensitiveContains("could not") ? DesignSystem.danger : DesignSystem.slate600)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
            }

            Color.clear.frame(height: 8)
        }
    }

    private var avatarCircle: some View {
        ZStack {
            ProfileAvatarView(
                name: profile.name,
                avatarPath: profile.avatarPath,
                size: 82,
                fallback: .initials
            )

            if isUploadingAvatar {
                Circle()
                    .fill(Color.black.opacity(0.36))
                    .frame(width: 82, height: 82)
                ProgressView()
                    .tint(.white)
            }
        }
    }

    private var avatarActions: some View {
        HStack(spacing: 8) {
            PhotosPicker(
                selection: $selectedPhotoItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                AppActionLabel(
                    title: profile.avatarPath.isEmpty ? "Add photo" : "Change photo",
                    icon: "camera.fill",
                    style: supabase.isSignedIn ? .secondary : .neutral,
                    size: .toolbar,
                    fullWidth: false,
                    disabled: !supabase.isSignedIn || isUploadingAvatar
                )
            }
            .buttonStyle(.plain)
            .disabled(!supabase.isSignedIn || isUploadingAvatar)

            if !profile.avatarPath.isEmpty {
                Button {
                    showRemoveAvatarConfirm = true
                } label: {
                    AppActionLabel(
                        title: "Remove",
                        icon: "trash",
                        style: .neutral,
                        size: .toolbar,
                        fullWidth: false,
                        disabled: isUploadingAvatar
                    )
                }
                .buttonStyle(.plain)
                .disabled(isUploadingAvatar)
            }
        }
    }

    private var syncBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(supabase.isSignedIn ? DesignSystem.bethanyGreen : DesignSystem.slate400)
                .frame(width: 7, height: 7)
            Text(supabase.isSignedIn
                 ? "Synced"
                 : "Local only - tap to back up")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignSystem.slate600)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(value: "\(currentStreak)", label: "Day streak", icon: "flame.fill", gold: true)
            Divider().frame(height: 44)
            statCell(value: "\(totalAnswered)", label: "Verses",     icon: "book.closed.fill")
            Divider().frame(height: 44)
            statCell(value: "\(Int(accuracy * 100))%", label: "Accuracy", icon: "target")
        }
        .padding(.vertical, 16)
        .background(DesignSystem.surface)
        .cornerRadius(16)
        .shadow(color: DesignSystem.shadow1, radius: 8, x: 0, y: 2)
    }

    private func statCell(value: String, label: String, icon: String, gold: Bool = false) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(gold ? DesignSystem.pastoralGold : DesignSystem.deepBlue)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(gold ? DesignSystem.goldText : DesignSystem.ink)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(DesignSystem.slate400)
        }
        .frame(maxWidth: .infinity)
    }

    private func prepareSelectedAvatar(_ item: PhotosPickerItem?) {
        guard let item else { return }
        guard supabase.isSignedIn else {
            avatarStatus = "Sign in before uploading a profile photo."
            selectedPhotoItem = nil
            return
        }

        isUploadingAvatar = true
        avatarStatus = "Loading photo..."

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw ProfileAvatarProcessingError.unreadableImage
                }

                let image = try Self.normalizedAvatarSource(from: data)

                await MainActor.run {
                    avatarCropSource = ProfileAvatarCropSource(image: image)
                    avatarStatus = ""
                    isUploadingAvatar = false
                    selectedPhotoItem = nil
                }
            } catch {
                await MainActor.run {
                    avatarStatus = "Could not load photo: \(error.localizedDescription)"
                    isUploadingAvatar = false
                    selectedPhotoItem = nil
                }
            }
        }
    }

    private func uploadCroppedAvatar(_ jpegData: Data) {
        guard supabase.isSignedIn else {
            avatarStatus = "Sign in before uploading a profile photo."
            return
        }

        isUploadingAvatar = true
        avatarStatus = "Uploading photo..."

        Task {
            do {
                let previousPath = await MainActor.run { profile.avatarPath }
                let newPath = try await supabase.uploadProfileAvatar(
                    jpegData: jpegData,
                    previousPath: previousPath
                )

                await MainActor.run {
                    profile.avatarPath = newPath
                    avatarStatus = "Photo updated"
                    isUploadingAvatar = false
                    selectedPhotoItem = nil
                }
            } catch {
                await MainActor.run {
                    avatarStatus = "Could not upload photo: \(error.localizedDescription)"
                    isUploadingAvatar = false
                    selectedPhotoItem = nil
                }
            }
        }
    }

    private func removeAvatar() {
        guard !profile.avatarPath.isEmpty else { return }
        let path = profile.avatarPath

        isUploadingAvatar = true
        avatarStatus = "Removing photo..."

        Task {
            do {
                try await supabase.removeProfileAvatar(path: path)
                await MainActor.run {
                    profile.avatarPath = ""
                    avatarStatus = "Photo removed"
                    isUploadingAvatar = false
                }
            } catch {
                await MainActor.run {
                    avatarStatus = "Could not remove photo: \(error.localizedDescription)"
                    isUploadingAvatar = false
                }
            }
        }
    }

    nonisolated private static func normalizedAvatarSource(from data: Data) throws -> UIImage {
        guard let source = UIImage(data: data) else {
            throw ProfileAvatarProcessingError.unreadableImage
        }
        guard source.size.width > 0, source.size.height > 0 else {
            throw ProfileAvatarProcessingError.unreadableImage
        }
        guard source.imageOrientation != .up else {
            return source
        }

        let renderer = UIGraphicsImageRenderer(size: source.size)
        return renderer.image { _ in
            source.draw(in: CGRect(origin: .zero, size: source.size))
        }
    }

    // MARK: - Sync section

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Account & Sync")

            if supabase.isSignedIn {
                signedInCard
            } else {
                signedOutCard
            }
        }
    }

    private var signedInCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.icloud.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(DesignSystem.bethanyGreen)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Progress is backed up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DesignSystem.ink)
                    Text("Your streak and settings are synced across devices with this account.")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.slate600)
                        .fixedSize(horizontal: false, vertical: true)
                    if !supabase.userEmail.isEmpty {
                        Text(supabase.userEmail)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DesignSystem.slate400)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(16)

            Divider().padding(.leading, 16)

            Button {
                showSignOutConfirm = true
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(DesignSystem.danger)
                    Text("Sign out")
                        .foregroundStyle(DesignSystem.danger)
                    Spacer()
                }
                .padding(16)
            }
        }
        .background(DesignSystem.surface)
        .cornerRadius(16)
        .shadow(color: DesignSystem.shadow1, radius: 6, x: 0, y: 2)
        .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task { await supabase.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your data stays on this device. Sign back in anytime to re-sync.")
        }
    }

    private var signedOutCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 22))
                    .foregroundStyle(DesignSystem.slate400)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Back up your progress")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DesignSystem.ink)
                    Text("Sign in with Apple or email OTP to sync your streak, alarms, and settings across your devices.")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.slate600)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await supabase.handleSignInResult(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .cornerRadius(13)

            EmailOTPAuthView(
                title: "Sign in with email",
                subtitle: "Use a one-time code. No password or separate signup screen.",
                showsContainer: false,
                successActionTitle: nil,
                onSuccess: nil
            )
        }
        .padding(16)
        .background(DesignSystem.surface)
        .cornerRadius(16)
        .shadow(color: DesignSystem.shadow1, radius: 6, x: 0, y: 2)
    }
}
