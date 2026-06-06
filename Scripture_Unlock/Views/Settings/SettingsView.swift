import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var profiles: [UserProfile]
    @Environment(SupabaseService.self) private var supabase

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    profileEntry
                    appearanceSection
                    scriptureSection
                    alarmSection
                    accountSection
                    appFooter
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 34)
            }
            .background(DesignSystem.warmCream.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .tint(DesignSystem.royalBlue)
        }
    }

    private var profileEntry: some View {
        Group {
            if let profile {
                NavigationLink {
                    ProfileView(profile: profile)
                } label: {
                    profileCard
                }
                .buttonStyle(.plain)
            } else {
                profileCard
            }
        }
    }

    private var profileCard: some View {
        HStack(spacing: 14) {
            avatar

            VStack(alignment: .leading, spacing: 5) {
                Text(profile?.name.isEmpty == false ? profile!.name : "Your profile")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(DesignSystem.ink)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Circle()
                        .fill(supabase.isSignedIn ? DesignSystem.bethanyGreen : DesignSystem.slate400)
                        .frame(width: 7, height: 7)
                    Text(syncSummary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignSystem.slate600)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DesignSystem.slate400)
        }
        .padding(16)
        .cardStyle()
    }

    private var appearanceSection: some View {
        settingsSection("Appearance") {
            AppearancePicker(profile: profile)
        }
    }

    private var scriptureSection: some View {
        settingsSection("Scripture") {
            menuRow(
                icon: "book.closed.fill",
                title: "Translation",
                subtitle: "Primary alarm and quiz Bible text",
                value: profile?.translationRaw ?? "ESV"
            ) {
                ForEach(Translation.allCases, id: \.self) { translation in
                    Button(translation.rawValue) {
                        profile?.translationRaw = translation.rawValue
                    }
                }
            }

            SettingsDivider()

            menuRow(
                icon: "globe",
                title: "Parallel Bible",
                subtitle: "Optional Ethiopian-language companion text",
                value: parallelLanguageLabel
            ) {
                Button("Off") { profile?.parallelLanguage = "" }
                Button("Amharic") { profile?.parallelLanguage = "am" }
                Button("Afaan Oromoo") { profile?.parallelLanguage = "or" }
                Button("Tigrigna") { profile?.parallelLanguage = "ti" }
            }
        }
    }

    private var alarmSection: some View {
        settingsSection("Alarm") {
            toggleRow(
                icon: "plusminus.circle.fill",
                title: "Snooze tax",
                subtitle: "Add one extra question after each snooze",
                isOn: Binding(
                    get: { profile?.snoozeTaxEnabled ?? true },
                    set: { profile?.snoozeTaxEnabled = $0 }
                )
            )

            SettingsDivider()

            toggleRow(
                icon: "moon.stars.fill",
                title: "Sabbath mode",
                subtitle: "Use one gentle question on Sundays",
                isOn: Binding(
                    get: { profile?.sabbathModeEnabled ?? true },
                    set: { profile?.sabbathModeEnabled = $0 }
                )
            )
        }
    }

    private var accountSection: some View {
        settingsSection("Account") {
            NavigationLink {
                AccountabilityView(profile: profile)
            } label: {
                navigationRow(
                    icon: "person.badge.shield.checkmark.fill",
                    title: "Accountability partner",
                    subtitle: "Share streak and accuracy with someone you trust"
                )
            }
            .buttonStyle(.plain)

            SettingsDivider()

            NavigationLink {
                LockItDownView()
            } label: {
                navigationRow(
                    icon: "lock.shield.fill",
                    title: "Block app deletion",
                    subtitle: "Open Screen Time protection steps"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var appFooter: some View {
        HStack(spacing: 12) {
            Image(systemName: "cross.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DesignSystem.pastoralGold)
                .frame(width: 34, height: 34)
                .background(DesignSystem.pastoralGold.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Scripture Unlock")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DesignSystem.ink)
                Text("v1.0 - Three verses to unlock the day")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.slate600)
            }

            Spacer()
        }
        .padding(.horizontal, 2)
    }

    private var avatar: some View {
        ProfileAvatarView(
            name: profile?.name ?? "",
            avatarPath: profile?.avatarPath ?? "",
            size: 52,
            fallback: .initials,
            showsGlow: false
        )
    }

    private var syncSummary: String {
        guard supabase.isSignedIn else { return "Local only - tap to back up" }
        return supabase.userEmail.isEmpty ? "Synced" : supabase.userEmail
    }

    private var parallelLanguageLabel: String {
        switch profile?.parallelLanguage ?? "" {
        case "am": return "Amharic"
        case "or": return "Afaan Oromoo"
        case "ti": return "Tigrigna"
        default: return "Off"
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title)
            VStack(spacing: 0) {
                content()
            }
            .background(DesignSystem.surface)
            .cornerRadius(16)
            .shadow(color: DesignSystem.shadow1, radius: 8, x: 0, y: 2)
        }
    }

    private func menuRow<MenuContent: View>(
        icon: String,
        title: String,
        subtitle: String,
        value: String,
        @ViewBuilder menu: () -> MenuContent
    ) -> some View {
        Menu {
            menu()
        } label: {
            HStack(spacing: 12) {
                rowIcon(icon)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DesignSystem.ink)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.slate600)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                HStack(spacing: 5) {
                    Text(value)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DesignSystem.royalBlue)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DesignSystem.royalBlue)
                }
            }
            .padding(15)
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(
        icon: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            rowIcon(icon)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DesignSystem.ink)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.slate600)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(DesignSystem.bethanyGreen)
        }
        .padding(15)
    }

    private func navigationRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            rowIcon(icon)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DesignSystem.ink)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.slate600)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DesignSystem.slate400)
        }
        .padding(15)
    }

    private func rowIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(DesignSystem.royalBlue)
            .frame(width: 36, height: 36)
            .background(DesignSystem.royalBlue.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 63)
    }
}

private struct AppearancePicker: View {
    let profile: UserProfile?

    private let options: [(label: String, value: String, icon: String)] = [
        ("System", "system", "circle.lefthalf.filled"),
        ("Light", "light", "sun.max.fill"),
        ("Dark", "dark", "moon.fill")
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.value) { option in
                let isSelected = (profile?.appearanceRaw ?? "system") == option.value

                Button {
                    profile?.appearanceRaw = option.value
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: option.icon)
                            .font(.system(size: 13, weight: .bold))
                        Text(option.label)
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .foregroundStyle(isSelected ? .white : DesignSystem.slate700)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(isSelected ? DesignSystem.deepBlue : DesignSystem.slate400.opacity(0.13))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.16), value: isSelected)
            }
        }
        .padding(12)
    }
}

struct AccountabilityView: View {
    let profile: UserProfile?
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("pastor@church.org", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DesignSystem.ink)
                        .padding(13)
                        .background(DesignSystem.warmCream)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(DesignSystem.slate400.opacity(0.22), lineWidth: 1)
                        )

                    Text("Your partner can see your streak and accuracy. They cannot change alarms or silence them.")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.slate600)
                        .fixedSize(horizontal: false, vertical: true)

                    AppActionButton(title: "Save", icon: "checkmark") {
                        profile?.accountabilityPartnerEmail = email
                        dismiss()
                    }
                }
                .padding(16)
                .cardStyle()
            }
            .padding(20)
        }
        .background(DesignSystem.warmCream.ignoresSafeArea())
        .navigationTitle("Accountability")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { email = profile?.accountabilityPartnerEmail ?? "" }
    }
}
