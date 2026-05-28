import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var context
    @Environment(AlarmService.self) private var alarmService

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            Form {
                Section("Scripture") {
                    Picker("Translation", selection: Binding(
                        get: { profile?.translationRaw ?? "ESV" },
                        set: { profile?.translationRaw = $0 }
                    )) {
                        ForEach(Translation.allCases, id: \.self) { t in Text(t.rawValue).tag(t.rawValue) }
                    }

                    Picker("Parallel translation", selection: Binding(
                        get: { profile?.parallelLanguage ?? "" },
                        set: { profile?.parallelLanguage = $0 }
                    )) {
                        Text("Off").tag("")
                        Text("አማርኛ  (Amharic)").tag("am")
                        Text("Afaan Oromoo  (Oromo)").tag("or")
                        Text("ትግርኛ  (Tigrigna)").tag("ti")
                    }
                }

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

                Section("Accountability") {
                    NavigationLink("Accountability partner") {
                        AccountabilityView(profile: profile)
                    }
                }

                Section("Lock it down") {
                    NavigationLink("Block app deletion (Screen Time)") {
                        LockItDownView()
                    }
                }

                Section("Developer") {
                    Button("Fire test alarm now") {
                        alarmService.fireTestAlarm()
                    }
                    .foregroundStyle(DesignSystem.royalBlue)

                    NavigationLink("Test AI question generator") {
                        AITestView()
                    }
                    .foregroundStyle(DesignSystem.royalBlue)
                }

                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Text("Scripture Unlock").font(.system(size: 13, weight: .semibold))
                            Text("v1.0 · Three verses to unlock the day")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
            .navigationTitle("Settings")
            .tint(DesignSystem.deepBlue)
        }
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
                    .keyboardType(.emailAddress).autocorrectionDisabled()
            }
            Section {
                Text("Your partner can see your streak and accuracy. They hold no power over your alarm — only you can silence it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("Save") { profile?.accountabilityPartnerEmail = email }
                    .tint(DesignSystem.royalBlue)
            }
        }
        .onAppear { email = profile?.accountabilityPartnerEmail ?? "" }
        .navigationTitle("Accountability")
    }
}
