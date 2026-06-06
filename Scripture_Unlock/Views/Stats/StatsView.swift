import SwiftUI
import SwiftData

struct StatsView: View {
    @Query(sort: \StreakEntry.date, order: .reverse) private var entries: [StreakEntry]

    private var currentStreak: Int {
        var count = 0; var d = Calendar.current.startOfDay(for: Date())
        while entries.contains(where: {
            Calendar.current.isDate($0.date, inSameDayAs: d) && $0.dismissedAt != nil
        }) {
            count += 1; d = Calendar.current.date(byAdding: .day, value: -1, to: d)!
        }
        return count
    }

    private var totalAnswered: Int { entries.reduce(0) { $0 + $1.questionsAnswered } }

    private var overallAccuracy: Double {
        let ans = entries.reduce(0) { $0 + $1.questionsAnswered }
        let cor = entries.reduce(0) { $0 + $1.questionsCorrect }
        return ans > 0 ? Double(cor) / Double(ans) : 0
    }

    private var streakMotivation: String {
        switch currentStreak {
        case 0:       return "Start today — every journey begins with one morning."
        case 1:       return "First day done. Keep it going tomorrow."
        case 2..<7:   return "Great start — you're building a real habit."
        case 7..<14:  return "One week strong. The Word is taking root."
        case 14..<30: return "Two weeks in — this is becoming second nature."
        case 30..<60: return "A full month of faithful mornings. Remarkable."
        case 60..<90: return "Sixty days of discipline. Your faith is growing."
        default:       return "A devotional life built one morning at a time."
        }
    }

    private var weekEntries: [(day: String, fraction: Double, today: Bool, snoozed: Bool)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            let d = cal.date(byAdding: .day, value: -offset, to: today)!
            let entry = entries.first { cal.isDate($0.date, inSameDayAs: d) }
            let isSunday = cal.component(.weekday, from: d) == 1
            let frac: Double = isSunday ? -1 : (entry?.questionsAnswered ?? 0) > 0
                ? min(Double(entry!.questionsCorrect) / Double(max(entry!.questionsAnswered, 1)), 1.0)
                : 0
            let label = cal.shortWeekdaySymbols[cal.component(.weekday, from: d) - 1]
            return (day: label, fraction: frac, today: offset == 0,
                    snoozed: (entry?.snoozeCount ?? 0) > 0)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "Devotional rhythm")
                        .padding(.horizontal, 20).padding(.top, 16)

                    streakHero
                        .padding(.horizontal, 20).padding(.top, 14)

                    weekChart
                        .padding(.horizontal, 20).padding(.top, 18)

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 12
                    ) {
                        MetricCard(
                            value: "\(totalAnswered)",
                            label: "Verses answered",
                            icon: "book.closed.fill"
                        )
                        MetricCard(
                            value: String(format: "%.0f%%", overallAccuracy * 100),
                            label: "Accuracy",
                            icon: "target",
                            gold: true
                        )
                        MetricCard(
                            value: "\(currentStreak)",
                            label: "Days unbroken",
                            icon: "flame.fill"
                        )
                        MetricCard(
                            value: "\(entries.count)",
                            label: "Sessions total",
                            icon: "calendar"
                        )
                    }
                    .padding(.horizontal, 20).padding(.top, 18)

                    recentVerses.padding(.top, 22)

                    Spacer(minLength: 32)
                }
            }
            .background(DesignSystem.warmCream.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Streak hero

    private var streakHero: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "0D1B3E"), Color(hex: "1E3A5F")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [DesignSystem.pastoralGold.opacity(0.22), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 220
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Unbroken streak")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2.5)
                    .textCase(.uppercase)
                    .foregroundStyle(DesignSystem.pastoralGold)

                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text("\(currentStreak)")
                        .font(.system(size: 72, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(currentStreak == 1 ? "day" : "days")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }

                Text(streakMotivation)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cornerRadius(20)
    }

    // MARK: - Week chart

    private var weekChart: some View {
        VStack(spacing: 12) {
            HStack {
                Text("This week")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DesignSystem.ink)
                Spacer()
                Text("\(totalAnswered) verses total")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.slate600)
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(weekEntries, id: \.day) { bar in
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(barColor(bar))
                            .frame(height: max(8, CGFloat(bar.fraction < 0 ? 0.2 : bar.fraction) * 90))
                        Text(bar.day)
                            .font(.system(size: 11, weight: bar.today ? .bold : .medium))
                            .foregroundStyle(bar.today ? DesignSystem.pastoralGold : DesignSystem.slate600)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 110, alignment: .bottom)

            // Legend
            HStack(spacing: 16) {
                legendDot(color: DesignSystem.pastoralGold, label: "Today")
                legendDot(color: DesignSystem.deepBlue, label: "Completed")
                legendDot(color: DesignSystem.warning.opacity(0.8), label: "Snoozed")
            }
            .font(.system(size: 10))
            .foregroundStyle(DesignSystem.slate400)
        }
        .padding(18)
        .cardStyle()
    }

    private func barColor(_ bar: (day: String, fraction: Double, today: Bool, snoozed: Bool)) -> AnyShapeStyle {
        if bar.today {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color(hex: "F0D898"), Color(hex: "C9A961")],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
        if bar.fraction < 0 {
            return AnyShapeStyle(DesignSystem.slate400.opacity(0.25))
        }
        if bar.snoozed {
            return AnyShapeStyle(DesignSystem.warning.opacity(0.7))
        }
        if bar.fraction > 0 {
            return AnyShapeStyle(DesignSystem.deepBlue.opacity(0.75))
        }
        return AnyShapeStyle(Color.primary.opacity(0.07))
    }

    private func legendDot(color: some ShapeStyle, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
        }
    }

    // MARK: - Recent verses

    private var recentVerses: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recently learned").padding(.horizontal, 20)
            if entries.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20))
                        .foregroundStyle(DesignSystem.pastoralGold)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No sessions yet")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DesignSystem.ink)
                        Text("Complete your first alarm to see the verses you've learned here.")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignSystem.slate600)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
                .padding(.horizontal, 20)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(DesignSystem.bethanyGreen)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(totalAnswered) verses answered across \(entries.count) sessions")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DesignSystem.ink)
                        Text("Keep up your streak to deepen your scriptural memory.")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignSystem.slate600)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - Metric card

struct MetricCard: View {
    let value: String
    let label: String
    var icon: String? = nil
    var gold = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(gold ? DesignSystem.pastoralGold : DesignSystem.deepBlue)
            }
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(gold ? DesignSystem.goldText : DesignSystem.deepBlue)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(DesignSystem.slate600)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}
