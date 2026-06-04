import SwiftUI

struct AlarmRowView: View {
    let alarm: Alarm
    let onToggle: () -> Void

    private var timeString: String {
        // alarm.hour stores 0–11 for both AM and PM; 0 should display as 12
        let displayHour = alarm.hour == 0 ? 12 : alarm.hour
        return String(format: "%d:%02d", displayHour, alarm.minute)
    }

    private var daysLabel: String {
        guard !alarm.repeatDays.isEmpty else { return "Once" }
        let names = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
        if alarm.repeatDays == [1,2,3,4,5] { return "Mon — Fri" }
        if alarm.repeatDays == Array(0...6)  { return "Every day" }
        return alarm.repeatDays.map { names[$0] }.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {

            // ── Accent bar ────────────────────────────────────────────────────
            RoundedRectangle(cornerRadius: 2)
                .fill(alarm.isEnabled
                      ? LinearGradient(
                          colors: [Color(hex: "F0D898"), Color(hex: "C9A961")],
                          startPoint: .top, endPoint: .bottom)
                      : LinearGradient(colors: [Color.clear, Color.clear],
                                       startPoint: .top, endPoint: .bottom))
                .frame(width: 3)
                .padding(.vertical, 16)
                .padding(.leading, 16)

            // ── Content ───────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 5) {

                // Time row
                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text(timeString)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignSystem.ink)
                    Text(alarm.isAM ? "AM" : "PM")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(alarm.isEnabled ? DesignSystem.pastoralGold : DesignSystem.slate400)
                        .padding(.bottom, 4)
                }

                // Label
                if !alarm.label.isEmpty {
                    Text(alarm.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignSystem.ink)
                }

                // Meta row
                HStack(spacing: 5) {
                    Text(daysLabel)
                    dot
                    Image(systemName: "book.fill").font(.system(size: 10))
                    Text(VersePack.find(alarm.packId).name)
                    dot
                    Text("\(alarm.questionCount) verse\(alarm.questionCount == 1 ? "" : "s")")
                }
                .font(.system(size: 11))
                .foregroundStyle(DesignSystem.slate400)
            }
            .padding(.leading, 14)
            .padding(.vertical, 14)
            .opacity(alarm.isEnabled ? 1 : 0.42)

            Spacer()

            // ── Toggle ────────────────────────────────────────────────────────
            Toggle("", isOn: Binding(get: { alarm.isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()
                .tint(DesignSystem.bethanyGreen)
                .padding(.trailing, 18)
        }
    }

    private var dot: some View {
        Circle().fill(DesignSystem.slate400.opacity(0.6)).frame(width: 3, height: 3)
    }
}
