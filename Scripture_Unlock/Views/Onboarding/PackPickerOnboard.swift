import SwiftUI

/// Onboarding pack picker — shows descriptions, not just names.
struct PackPickerOnboard: View {
    let profile: UserProfile
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OnboardingDots(total: 5, current: 3).frame(maxWidth: .infinity).padding(.top, 16)

                Text("Your first pack")
                    .font(.system(size: 11, weight: .bold)).tracking(2.5).textCase(.uppercase)
                    .foregroundStyle(DesignSystem.slate600).padding(.top, 36)

                Text("Where will the\nverses come from?")
                    .font(.system(size: 28, weight: .bold)).foregroundStyle(DesignSystem.ink).padding(.top, 10)

                Text("Pick one to start. You can switch packs or mix them anytime.")
                    .font(.system(size: 14)).foregroundStyle(DesignSystem.slate600).padding(.top, 6)

                VStack(spacing: 10) {
                    ForEach(VersePack.all) { pack in
                        let on = profile.activePackId == pack.id
                        Button { profile.activePackId = pack.id } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(hex: pack.colorHex)).frame(width: 40, height: 40)
                                    Image(systemName: pack.iconName).foregroundStyle(.white)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                                        Text(pack.name).font(.system(size: 16, weight: .bold)).foregroundStyle(DesignSystem.ink)
                                        Text("\(pack.questionCount) verses").font(.system(size: 11)).foregroundStyle(DesignSystem.slate400)
                                    }
                                    Text(pack.description).font(.system(size: 12)).foregroundStyle(DesignSystem.slate600)
                                }
                                Spacer()
                                if on {
                                    ZStack {
                                        Circle().fill(Color(hex: pack.colorHex)).frame(width: 24, height: 24)
                                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                    }
                                }
                            }
                            .padding(14)
                            .background(DesignSystem.surface)
                            .cornerRadius(16)
                            .overlay(RoundedRectangle(cornerRadius: 16)
                                .stroke(on ? Color(hex: pack.colorHex) : Color.clear, lineWidth: 2))
                            .shadow(color: DesignSystem.shadow1, radius: 6, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 22)

                Spacer(minLength: 40)
                PrimaryButton(title: "Continue", icon: "chevron.right", action: onContinue).padding(.bottom, 48)
            }
            .padding(.horizontal, 24)
        }
        .background(DesignSystem.warmCream.ignoresSafeArea())
    }
}

// MARK: - First alarm setup

struct FirstAlarmView: View {
    let profile: UserProfile
    let onContinue: () -> Void

    @State private var selectedTime: Date = {
        var c = Calendar.current.dateComponents([.year,.month,.day], from: Date())
        c.hour = 6; c.minute = 0
        return Calendar.current.date(from: c) ?? Date()
    }()
    @State private var selectedDays: [Int] = [1,2,3,4,5]

    private let quickTimes = ["5:30","6:00","6:30","7:00"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OnboardingDots(total: 5, current: 4).frame(maxWidth: .infinity).padding(.top, 16)

                Text("Your first alarm")
                    .font(.system(size: 11, weight: .bold)).tracking(2.5).textCase(.uppercase)
                    .foregroundStyle(DesignSystem.slate600).padding(.top, 36)

                Text("When does tomorrow start?")
                    .font(.system(size: 28, weight: .bold)).foregroundStyle(DesignSystem.ink).padding(.top, 10)

                Text("We recommend a time that gives you 10 quiet minutes after the alarm.")
                    .font(.system(size: 14)).foregroundStyle(DesignSystem.slate600).padding(.top, 6)

                VStack(spacing: 0) {
                    DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)

                    Divider().padding(.horizontal, 12)

                    VStack(spacing: 8) {
                        Text("Quick pick")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(2)
                            .textCase(.uppercase)
                            .foregroundStyle(DesignSystem.slate400)

                        HStack(spacing: 8) {
                            ForEach(quickTimes, id: \.self) { t in
                                let isSelected = formatTime(selectedTime) == t
                                Button { setTime(t) } label: {
                                    Text(t)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(isSelected ? .white : DesignSystem.slate600)
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .background(isSelected ? DesignSystem.deepBlue : Color.primary.opacity(0.05))
                                        .cornerRadius(999)
                                        .overlay(RoundedRectangle(cornerRadius: 999)
                                            .stroke(isSelected ? Color.clear : Color.primary.opacity(0.12), lineWidth: 0.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 14)
                }
                .background(DesignSystem.surface)
                .cornerRadius(20)
                .overlay(alignment: .top) {
                    Rectangle().fill(DesignSystem.goldGradient).frame(height: 3).cornerRadius(3)
                }
                .shadow(color: DesignSystem.shadow1, radius: 8, x: 0, y: 2)
                .padding(.top, 22)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Repeat").font(.system(size: 11, weight: .bold)).tracking(2).textCase(.uppercase).foregroundStyle(DesignSystem.slate600)
                    DayPicker(selectedDays: $selectedDays)
                }
                .padding(.top, 22)

                HStack(spacing: 10) {
                    Image(systemName: "shield.fill").foregroundStyle(DesignSystem.goldText)
                    Text("Defaults: **3 verses · Regular · \(VersePack.find(profile.activePackId).name)**. Adjust anytime.")
                        .font(.system(size: 12.5)).foregroundStyle(DesignSystem.slate700)
                }
                .padding(12)
                .background(DesignSystem.pastoralGold.opacity(0.12))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(DesignSystem.pastoralGold.opacity(0.35), lineWidth: 0.5))
                .padding(.top, 18)

                Spacer(minLength: 40)
                PrimaryButton(title: "Set my alarm", icon: "bell.fill") {
                    saveAlarm(); onContinue()
                }
                .padding(.bottom, 12)
                Text("You can add more alarms after this one.")
                    .font(.system(size: 12)).foregroundStyle(DesignSystem.slate400)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 48)
            }
            .padding(.horizontal, 24)
        }
        .background(DesignSystem.warmCream.ignoresSafeArea())
    }

    private func formatTime(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour,.minute], from: date)
        let h = c.hour ?? 6
        let m = c.minute ?? 0
        let displayH = h > 12 ? h - 12 : (h == 0 ? 12 : h)
        return String(format: "%d:%02d", displayH, m)
    }

    private func setTime(_ t: String) {
        let parts = t.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        var c = Calendar.current.dateComponents([.year,.month,.day], from: Date())
        c.hour = parts[0]; c.minute = parts[1]
        selectedTime = Calendar.current.date(from: c) ?? Date()
    }

    private func saveAlarm() {
        let comps = Calendar.current.dateComponents([.hour,.minute], from: selectedTime)
        let h = comps.hour ?? 6
        let alarm = Alarm(label: "Morning devotions", hour: h > 12 ? h - 12 : h, minute: comps.minute ?? 0)
        alarm.isAM = h < 12
        alarm.repeatDays = selectedDays
        alarm.packId = profile.activePackId
        Task { try? await AlarmService.shared.schedule(alarm) }
    }
}
