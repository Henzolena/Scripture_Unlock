import SwiftUI
import SwiftData

struct StatsView: View {
    @Query(sort: \StreakEntry.date, order: .reverse) private var entries: [StreakEntry]

    private var currentStreak: Int {
        var count = 0; var d = Calendar.current.startOfDay(for: Date())
        while entries.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: d) && $0.dismissedAt != nil }) {
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
            return (day: label, fraction: frac, today: offset == 0, snoozed: (entry?.snoozeCount ?? 0) > 0)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "Your devotional rhythm")
                        .padding(.horizontal, 20).padding(.top, 16)

                    streakHero.padding(.horizontal, 20).padding(.top, 14)
                    weekChart.padding(.horizontal, 20).padding(.top, 18)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricCard(value: "\(totalAnswered)", label: "Verses answered")
                        MetricCard(value: String(format: "%.0f%%", overallAccuracy * 100), label: "Accuracy", gold: true)
                        MetricCard(value: "\(currentStreak)", label: "Days unbroken")
                        MetricCard(value: "0:18", label: "Avg. wake time")
                    }
                    .padding(.horizontal, 20).padding(.top, 18)

                    recentVerses.padding(.top, 22)

                    Spacer(minLength: 32)
                }
            }
            .background(DesignSystem.warmCream.ignoresSafeArea())
            .navigationTitle("Streak")
        }
    }

    private var streakHero: some View {
        ZStack {
            DesignSystem.deepBlueGradient
            RadialGradient(colors: [DesignSystem.pastoralGold.opacity(0.20), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 200)
            VStack(alignment: .leading, spacing: 6) {
                Text("Unbroken streak").font(.system(size: 11, weight: .bold)).tracking(2.5).textCase(.uppercase).foregroundStyle(DesignSystem.pastoralGold)
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text("\(currentStreak)").font(.system(size: 72, weight: .heavy, design: .monospaced)).foregroundStyle(.white)
                    Text("days").font(.system(size: 20, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                }
                Text("Keep going — you're on a roll.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
            }
            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .cornerRadius(20)
    }

    private var weekChart: some View {
        VStack(spacing: 12) {
            HStack {
                Text("This week").font(.system(size: 13, weight: .bold)).foregroundStyle(DesignSystem.ink)
                Spacer()
                Text("\(totalAnswered) verses total").font(.system(size: 12)).foregroundStyle(DesignSystem.slate600)
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(weekEntries, id: \.day) { bar in
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(bar.fraction < 0  ? DesignSystem.slate400.opacity(0.3) :
                                  bar.today         ? DesignSystem.pastoralGold :
                                  bar.snoozed       ? DesignSystem.warning :
                                  bar.fraction > 0  ? DesignSystem.deepBlue :
                                                      Color.primary.opacity(0.08))
                            .frame(height: max(8, CGFloat(bar.fraction < 0 ? 0.25 : bar.fraction) * 90))
                        Text(bar.day).font(.system(size: 11, weight: bar.today ? .bold : .medium))
                            .foregroundStyle(bar.today ? DesignSystem.pastoralGold : DesignSystem.slate600)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 110, alignment: .bottom)
        }
        .padding(18).cardStyle()
    }

    private var recentVerses: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recently learned").padding(.horizontal, 20)
            VStack(spacing: 0) {
                ForEach(TriviaQuestion.samples.prefix(3)) { q in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(q.verseRef.uppercased()).font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(DesignSystem.pastoralGold)
                        Text("\u{201C}\(q.verseText)\u{201D}").font(DesignSystem.serif(13, italic: true)).foregroundStyle(DesignSystem.slate600).lineLimit(2)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    if q.id != TriviaQuestion.samples.prefix(3).last?.id { Divider().padding(.leading, 16) }
                }
            }
            .cardStyle().padding(.horizontal, 20)
        }
    }
}

struct MetricCard: View {
    let value: String; let label: String; var gold = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(gold ? DesignSystem.goldText : DesignSystem.deepBlue)
            Text(label).font(.system(size: 12)).foregroundStyle(DesignSystem.slate600)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).cardStyle()
    }
}
