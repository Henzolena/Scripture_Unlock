import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var context
    @Environment(SupabaseService.self) private var supabase

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            Form {

                // ── Profile ───────────────────────────────────────────────────
                Section {
                    NavigationLink {
                        if let p = profile { ProfileView(profile: p) }
                    } label: {
                        profileRow
                    }
                }

                // ── Appearance ────────────────────────────────────────────────
                Section {
                    AppearancePicker(profile: profile)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Changes apply instantly across the entire app.")
                }

                // ── Scripture ─────────────────────────────────────────────────
                Section("Scripture") {
                    Picker("Translation", selection: Binding(
                        get: { profile?.translationRaw ?? "ESV" },
                        set: { profile?.translationRaw = $0 }
                    )) {
                        ForEach(Translation.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t.rawValue)
                        }
                    }

                    Picker("Parallel translation", selection: Binding(
                        get: { profile?.parallelLanguage ?? "" },
                        set: { profile?.parallelLanguage = $0 }
                    )) {
                        Text("Off").tag("")
                        Text("Amharic").tag("am")
                        Text("Afaan Oromoo").tag("or")
                        Text("Tigrigna").tag("ti")
                    }
                }

                // ── Alarm ─────────────────────────────────────────────────────
                Section("Alarm") {
                    Toggle("Snooze tax (+1 per snooze)", isOn: Binding(
                        get: { profile?.snoozeTaxEnabled ?? true },
                        set: { profile?.snoozeTaxEnabled = $0 }
                    ))
                    .tint(DesignSystem.bethanyGreen)

                    Toggle("Sabbath mode (1 question on Sundays)", isOn: Binding(
                        get: { profile?.sabbathModeEnabled ?? true },
                        set: { profile?.sabbathModeEnabled = $0 }
                    ))
                    .tint(DesignSystem.bethanyGreen)
                }

                // ── Accountability ────────────────────────────────────────────
                Section("Accountability") {
                    NavigationLink("Accountability partner") {
                        AccountabilityView(profile: profile)
                    }
                }

                // ── Lock it down ──────────────────────────────────────────────
                Section("Lock it down") {
                    NavigationLink("Block app deletion (Screen Time)") {
                        LockItDownView()
                    }
                }

                // ── About ─────────────────────────────────────────────────────
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Text("Scripture Unlock")
                                .font(.system(size: 13, weight: .semibold))
                            Text("v1.0 · Three verses to unlock the day")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
            .navigationTitle("Settings")
            .tint(DesignSystem.deepBlue)
        }
    }

    // MARK: - Profile row

    private var profileRow: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(DesignSystem.goldGradient)
                    .frame(width: 46, height: 46)
                Text(initials)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(hex: "1E3A5F"))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(profile?.name.isEmpty == false ? profile!.name : "Your profile")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignSystem.ink)
                HStack(spacing: 4) {
                    Circle()
                        .fill(supabase.isSignedIn ? DesignSystem.bethanyGreen : DesignSystem.slate400)
                        .frame(width: 6, height: 6)
                    Text(supabase.isSignedIn ? "Synced" : "Local only — tap to back up")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.slate600)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var initials: String {
        let name = profile?.name ?? ""
        let parts = name.split(separator: " ")
        if parts.count >= 2 { return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased() }
        let s = String(name.prefix(2)).uppercased()
        return s.isEmpty ? "?" : s
    }
}

// MARK: - Appearance Picker

/// Segmented control for light / dark / system theme.
/// Lives in its own view so it can use @Environment(\.colorScheme)
/// purely for the preview icons — the actual scheme is driven by RootView.
private struct AppearancePicker: View {
    let profile: UserProfile?
    @Environment(\.colorScheme) private var currentScheme

    private let options: [(label: String, value: String, icon: String)] = [
        ("Light",  "light",  "sun.max.fill"),
        ("System", "system", "circle.lefthalf.filled"),
        ("Dark",   "dark",   "moon.fill"),
    ]

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ForEach(options, id: \.value) { option in
                    let isSelected = (profile?.appearanceRaw ?? "system") == option.value

                    Button {
                        profile?.appearanceRaw = option.value
                    } label: {
                        VStack(spacing: 8) {
                            // Preview tile
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(option.value == "dark"
                                          ? Color(hex: "111827")
                                          : option.value == "light"
                                            ? Color(hex: "FAF7F2")
                                            : Color(hex: currentScheme == .dark ? "111827" : "FAF7F2"))
                                    .frame(height: 52)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(
                                                isSelected
                                                    ? DesignSystem.pastoralGold
                                                    : Color.primary.opacity(0.12),
                                                lineWidth: isSelected ? 2 : 1
                                            )
                                    )

                                Image(systemName: option.icon)
                                    .font(.system(size: 20))
                                    .foregroundStyle(
                                        option.value == "dark"
                                            ? Color(hex: "C9A961")
                                            : option.value == "light"
                                              ? Color(hex: "1E3A5F")
                                              : DesignSystem.pastoralGold
                                    )
                            }

                            Text(option.label)
                                .font(.system(size: 12, weight: isSelected ? .bold : .regular))
                                .foregroundStyle(isSelected ? DesignSystem.pastoralGold : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Accountability

struct AccountabilityView: View {
    let profile: UserProfile?
    @State private var email = ""

    var body: some View {
        Form {
            Section("Partner email") {
                TextField("pastor@church.org", text: $email)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
            }
            Section {
                Text("Your partner can see your streak and accuracy. They hold no power over your alarm — only you can silence it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Save") {
                    profile?.accountabilityPartnerEmail = email
                }
                .tint(DesignSystem.royalBlue)
            }
        }
        .onAppear { email = profile?.accountabilityPartnerEmail ?? "" }
        .navigationTitle("Accountability")
    }
}
