import SwiftUI

struct AlarmRowView: View {
    let alarm: Alarm
    let onToggle: () -> Void

    private var timeString: String {
        String(format: "%d:%02d", alarm.hour, alarm.minute)
    }

    private var daysLabel: String {
        guard !alarm.repeatDays.isEmpty else { return "Once" }
        let names = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
        if alarm.repeatDays == [1,2,3,4,5] { return "Mon — Fri" }
        if alarm.repeatDays == Array(0...6) { return "Every day" }
        return alarm.repeatDays.map { names[$0] }.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            if alarm.isEnabled {
                Rectangle()
                    .fill(DesignSystem.pastoralGold)
                    .frame(width: 2)
                    .padding(.vertical, 14)
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 2)
                    .padding(.vertical, 14)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(timeString)
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignSystem.ink)
                    Text(alarm.isAM ? "AM" : "PM")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignSystem.slate600)
                }

                Text(alarm.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.ink)

                HStack(spacing: 6) {
                    Text(daysLabel)
                    dot
                    Image(systemName: "book.fill").font(.system(size: 10))
                    Text(VersePack.find(alarm.packId).name)
                    dot
                    Text("\(alarm.questionCount) verse\(alarm.questionCount == 1 ? "" : "s")")
                }
                .font(.system(size: 12))
                .foregroundStyle(DesignSystem.slate600)
            }
            .padding(.leading, 16)
            .padding(.vertical, 14)
            .opacity(alarm.isEnabled ? 1 : 0.45)

            Spacer()

            Toggle("", isOn: Binding(get: { alarm.isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()
                .tint(DesignSystem.bethanyGreen)
                .padding(.trailing, 18)
        }
    }

    private var dot: some View {
        Circle().fill(DesignSystem.slate400).frame(width: 3, height: 3)
    }
}
