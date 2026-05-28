import SwiftUI
import SwiftData

/// Root navigator — decides between Onboarding and the main app.
/// Also intercepts when AlarmService fires an alarm mid-use.
struct RootView: View {
    @Environment(AlarmService.self) private var alarmService
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            if profiles.isEmpty {
                OnboardingFlow()
            } else {
                MainTabView()
                    .fullScreenCover(item: Binding(
                        get: { alarmService.activeAlarm },
                        set: { _ in }          // dismissal only via trivia completion
                    )) { alarm in
                        RingingView(alarm: alarm)
                            .interactiveDismissDisabled(true)
                    }
            }
        }
        // When user backs out of the alarm screen, fire a re-engagement notification
        // within 4 seconds so the alarm sound re-asserts itself
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background, alarmService.activeAlarm != nil {
                alarmService.scheduleReengagementNotification()
            } else if newPhase == .active {
                alarmService.cancelReengagementNotification()
            }
        }
    }
}

// MARK: - Main tab bar

struct MainTabView: View {
    @State private var selectedTab: Tab = .home

    enum Tab { case home, stats, packs, bible, settings }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Alarms",   systemImage: "alarm.fill") }
                .tag(Tab.home)

            StatsView()
                .tabItem { Label("Streak",   systemImage: "flame.fill") }
                .tag(Tab.stats)

            PacksView()
                .tabItem { Label("Verses",   systemImage: "book.fill") }
                .tag(Tab.packs)

            BibleView()
                .tabItem { Label("Bible",    systemImage: "books.vertical.fill") }
                .tag(Tab.bible)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .tint(DesignSystem.deepBlue)
    }
}
