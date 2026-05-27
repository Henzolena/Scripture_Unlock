import SwiftUI
import SwiftData

/// Root navigator — decides between Onboarding and the main app.
/// Also intercepts when AlarmService fires an alarm mid-use.
struct RootView: View {
    @Environment(AlarmService.self) private var alarmService
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            if profiles.isEmpty {
                OnboardingFlow()
            } else {
                MainTabView()
                    // Full-screen alarm sheet — overrides everything
                    .fullScreenCover(item: Binding(
                        get: { alarmService.activeAlarm },
                        set: { _ in }
                    )) { alarm in
                        RingingView(alarm: alarm)
                    }
            }
        }
    }
}

// MARK: - Main tab bar

struct MainTabView: View {
    @State private var selectedTab: Tab = .home

    enum Tab { case home, stats, packs, settings }

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

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .tint(DesignSystem.deepBlue)
    }
}
