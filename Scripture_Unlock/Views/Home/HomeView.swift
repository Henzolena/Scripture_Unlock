import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Alarm.createdAt) private var alarms: [Alarm]
    @Query private var profiles: [UserProfile]
    @Query private var streaks: [StreakEntry]
    @State private var vm = AlarmListViewModel()
    @State private var showingNewAlarm = false

    private var profile: UserProfile? { profiles.first }
    private var currentStreak: Int {
        var count = 0
        var date = Calendar.current.startOfDay(for: Date())
        while streaks.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: date) && $0.dismissedAt != nil }) {
            count += 1
            date = Calendar.current.date(byAdding: .day, value: -1, to: date)!
        }
        return count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    greetingHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 20)

                    VerseCard(
                        reference: "Psalm 5:3",
                        text: "O Lord, in the morning you hear my voice; in the morning I prepare a sacrifice for you and watch.",
                        translation: "ESV"
                    )
                    .padding(.horizontal, 20)

                    alarmSection
                        .padding(.top, 28)

                    if profile?.sabbathModeEnabled == true {
                        sabbathBanner
                            .padding(.horizontal, 20)
                            .padding(.top, 18)
                    }

                    Spacer(minLength: 32)
                }
            }
            .background(DesignSystem.warmCream.ignoresSafeArea())
            .navigationTitle("Scripture Unlock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingNewAlarm = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    .tint(DesignSystem.deepBlue)
                }
            }
            .sheet(isPresented: $showingNewAlarm) {
                SetAlarmView(alarm: Alarm())
            }
        }
    }

    // MARK: - Sub-views

    private var greetingHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.slate600)
                Group {
                    Text("Good morning,\n") + Text(profile?.name ?? "friend")
                        .foregroundColor(DesignSystem.deepBlue)
                }
                .font(.system(size: 30, weight: .bold, design: .default))
                .foregroundStyle(DesignSystem.ink)

                if currentStreak > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(DesignSystem.pastoralGold)
                            .font(.system(size: 14))
                        Text("\(currentStreak)-day streak")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: "9C7E3B"))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(DesignSystem.pastoralGold.opacity(0.14))
                    .cornerRadius(999)
                }
            }
            Spacer()
        }
    }

    private var alarmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Your alarms").padding(.horizontal, 20)
                Spacer()
            }

            if alarms.isEmpty {
                Text("No alarms yet — tap + to add one.")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignSystem.slate400)
                    .padding(.horizontal, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(alarms) { alarm in
                        AlarmRowView(alarm: alarm) {
                            vm.toggle(alarm)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                vm.delete(alarm, context: context)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        if alarm.id != alarms.last?.id {
                            Divider().padding(.leading, 20)
                        }
                    }
                }
                .background(DesignSystem.surface)
                .cornerRadius(16)
                .shadow(color: DesignSystem.shadow1, radius: 8, x: 0, y: 2)
                .padding(.horizontal, 20)
            }
        }
    }

    private var sabbathBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "bird.fill")
                .foregroundStyle(DesignSystem.royalBlue)
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 2) {
                Text("Sabbath mode")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DesignSystem.deepBlue)
                Text("Sunday alarms use gentle tones and one question only.")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.slate600)
            }
        }
        .padding(14)
        .background(DesignSystem.royalBlue.opacity(0.06))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DesignSystem.royalBlue.opacity(0.18), lineWidth: 0.5))
    }
}
