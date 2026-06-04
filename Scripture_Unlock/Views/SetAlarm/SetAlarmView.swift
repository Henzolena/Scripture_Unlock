import SwiftUI
import SwiftData

struct SetAlarmView: View {
    @Environment(\.dismiss)       private var dismiss
    @Environment(\.modelContext)  private var context
    @Environment(SupabaseService.self) private var supabase
    @State var alarm: Alarm
    var isNew: Bool = true

    @State private var showTonePicker = false
    @State private var previewPlayer  = TonePreviewPlayer.shared

    private var selectedTone: AlarmTone {
        AlarmTone.find(id: alarm.toneIdentifier)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }

                Section("Repeat") {
                    DayPicker(selectedDays: $alarm.repeatDays)
                }

                Section("Sound") {
                    NavigationLink {
                        TonePickerView(selectedId: $alarm.toneIdentifier)
                    } label: {
                        HStack {
                            Text(selectedTone.emoji)
                            Text(selectedTone.displayName)
                            Spacer()
                        }
                    }
                }

                Section("Dismissal") {
                    NavigationLink {
                        PackPickerView(selectedPackId: $alarm.packId)
                    } label: {
                        LabeledContent("Verse pack", value: VersePack.find(alarm.packId).name)
                    }

                    Picker("Translation", selection: $alarm.translation) {
                        ForEach(Translation.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }

                    Picker("Questions", selection: $alarm.questionCount) {
                        ForEach([1, 3, 5], id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Difficulty", selection: $alarm.difficulty) {
                        ForEach(Difficulty.allCases, id: \.self) { d in
                            Text(d.rawValue).tag(d)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle(isOn: Binding(
                        get: { true },
                        set: { _ in }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Snooze tax")
                            Text("+1 question per snooze")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tint(DesignSystem.bethanyGreen)
                }

                Section("Label") {
                    TextField("Morning devotions", text: $alarm.label)
                }

                if !isNew {
                    Section {
                        Button("Delete alarm", role: .destructive) {
                            let id = alarm.id
                            context.delete(alarm)
                            Task { await supabase.deleteAlarm(id: id) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New alarm" : "Edit alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        previewPlayer.stop()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        previewPlayer.stop()
                        if isNew { context.insert(alarm) }
                        Task {
                            try? await AlarmService.shared.schedule(alarm)
                            await supabase.upsertAlarm(alarm)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .tint(DesignSystem.royalBlue)
                }
            }
            .tint(DesignSystem.deepBlue)
        }
    }

    // MARK: - Helpers

    private var timeBinding: Binding<Date> {
        Binding {
            var comps = Calendar.current.dateComponents([.year,.month,.day], from: Date())
            comps.hour = alarm.isAM ? alarm.hour : alarm.hour + 12
            comps.minute = alarm.minute
            return Calendar.current.date(from: comps) ?? Date()
        } set: { date in
            let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
            let h = comps.hour ?? 6
            alarm.isAM = h < 12
            alarm.hour = alarm.isAM ? h : h - 12
            alarm.minute = comps.minute ?? 0
        }
    }
}

// MARK: - Tone picker

struct TonePickerView: View {
    @Binding var selectedId: String
    @Environment(\.dismiss) private var dismiss
    @State private var player = TonePreviewPlayer.shared

    var body: some View {
        List {
            ForEach(AlarmTone.all) { tone in
                Button {
                    selectedId = tone.id
                    player.preview(tone)
                } label: {
                    HStack(spacing: 14) {
                        Text(tone.emoji)
                            .font(.system(size: 22))
                            .frame(width: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(tone.displayName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.primary)
                            Text(tone.description)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if player.playingId == tone.id {
                            // Animated speaker while playing
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(DesignSystem.royalBlue)
                                .symbolEffect(.variableColor)
                        } else if selectedId == tone.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(DesignSystem.royalBlue)
                                .fontWeight(.semibold)
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Alarm Sound")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { player.stop() }
    }
}

// MARK: - Day picker

struct DayPicker: View {
    @Binding var selectedDays: [Int]
    private let labels = ["S","M","T","W","T","F","S"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<7) { day in
                let on = selectedDays.contains(day)
                Button {
                    if on { selectedDays.removeAll { $0 == day } }
                    else  { selectedDays.append(day); selectedDays.sort() }
                } label: {
                    Text(labels[day])
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(on ? .white : DesignSystem.slate600)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(on ? DesignSystem.deepBlue : Color.clear)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(on ? Color.clear : Color.primary.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
