import SwiftUI
import SwiftData
import AuthenticationServices

struct ProfileView: View {
    let profile: UserProfile
    @Environment(\.modelContext) private var context
    @Environment(SupabaseService.self) private var supabase
    @Query(sort: \StreakEntry.date, order: .reverse) private var entries: [StreakEntry]

    @State private var editingName       = false
    @State private var draftName         = ""
    @State private var showSignOutConfirm = false

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

    private var initials: String {
        let parts = profile.name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(profile.name.prefix(2)).uppercased()
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroHeader
                statsRow
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                syncSection
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                Spacer(minLength: 40)
            }
        }
        .background(DesignSystem.warmCream.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                // Manual sync button — pulls latest from Supabase immediately
                if supabase.isSignedIn {
                    Button {
                        Task { await supabase.syncFromCloud(context: context) }
                    } label: {
                        if supabase.isSyncing {
                            ProgressView().tint(DesignSystem.royalBlue)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DesignSystem.royalBlue)
                        }
                    }
                    .disabled(supabase.isSyncing)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(editingName ? "Save" : "Edit") {
                    if editingName {
                        profile.name = draftName.trimmingCharacters(in: .whitespaces)
                        Task { await supabase.upsertProfile(profile) }
                    } else {
                        draftName = profile.name
                    }
                    editingName.toggle()
                }
                .fontWeight(.semibold)
                .tint(DesignSystem.royalBlue)
            }
        }
    }

    // MARK: - Hero header

    private var heroHeader: some View {
        VStack(spacing: 0) {
            // Dark banner — avatar overlaps its bottom edge via overlay
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
            .frame(height: 140)
            .overlay(alignment: .bottom) {
                // Circle center sits ON the banner's bottom edge; lower half hangs below
                avatarCircle
            }

            // Reserve space for the bottom half of the avatar (88 / 2 = 44)
            Color.clear.frame(height: 44)

            // Name
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

            // Sync badge
            syncBadge
                .padding(.top, 6)

            // Diagnostic status — shown until cloud sync succeeds
            if !supabase.syncStatus.isEmpty {
                Text(supabase.syncStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(supabase.syncStatus.hasPrefix("✅") ? DesignSystem.bethanyGreen : DesignSystem.slate400)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 2)
            }

            Color.clear.frame(height: 20)
        }
    }

    private var avatarCircle: some View {
        ZStack {
            Circle()
                .fill(DesignSystem.goldGradient)
                .frame(width: 88, height: 88)
                .shadow(color: DesignSystem.pastoralGold.opacity(0.45), radius: 14)
            Text(initials.isEmpty ? "?" : initials)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color(hex: "1E3A5F"))
        }
    }

    private var syncBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(supabase.isSignedIn ? DesignSystem.bethanyGreen : DesignSystem.slate400)
                .frame(width: 7, height: 7)
            Text(supabase.isSignedIn
                 ? (supabase.userEmail.isEmpty ? "Synced" : "Synced · \(supabase.userEmail)")
                 : "Local only — tap to back up")
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
                    Text("Your streak and settings are synced across all devices signed in with your Apple ID.")
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
                    Text("Sign in with Apple to sync your streak, alarms, and settings across all your devices — privately and securely.")
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
        }
        .padding(16)
        .background(DesignSystem.surface)
        .cornerRadius(16)
        .shadow(color: DesignSystem.shadow1, radius: 6, x: 0, y: 2)
    }
}
