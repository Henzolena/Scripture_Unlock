import SwiftUI
import SwiftData

/// Root navigator — decides between Onboarding and the main app.
/// Also intercepts when AlarmService fires an alarm mid-use.
struct RootView: View {
    @Environment(AlarmService.self)     private var alarmService
    @Environment(SupabaseService.self)  private var supabase
    @Environment(\.modelContext)        private var context
    @Environment(\.scenePhase)          private var scenePhase
    @Query private var profiles: [UserProfile]
    @Query(sort: \Alarm.createdAt) private var alarms: [Alarm]

    /// Converts the stored appearance preference into a SwiftUI ColorScheme.
    /// `nil` means "follow the system setting" — the default.
    private var preferredColorScheme: ColorScheme? {
        switch profiles.first?.appearanceRaw {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    @State private var router = NavigationRouter()

    var body: some View {
        Group {
            if profiles.isEmpty {
                OnboardingFlow()
            } else {
                MainTabView(router: router)
                    .fullScreenCover(item: Binding(
                        get: { alarmService.activeAlarm },
                        set: { _ in }
                    )) { alarm in
                        RingingView(alarm: alarm)
                            .interactiveDismissDisabled(true)
                    }
            }
        }
        .environment(router)
        .preferredColorScheme(preferredColorScheme)
        // One-time startup: reschedule alarms + seed local data for new installs
        .task {
            let savedAlarms = (try? context.fetch(FetchDescriptor<Alarm>())) ?? []
            await alarmService.rescheduleAll(savedAlarms)
            if !supabase.isSignedIn {
                SeedDataService.seedIfNeeded(context: context)
            }
        }
        // Sync whenever sign-in state changes (also fires once on launch with
        // the initial value, which is fine — syncFromCloud guards against
        // concurrent calls and is a no-op when isSignedIn is false).
        .task(id: supabase.isSignedIn) {
            if supabase.isSignedIn {
                await supabase.syncFromCloud(context: context)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // App came to foreground — stop background alarm monitoring.
                // Sync is handled by .task(id: isSignedIn) when state changes;
                // we do NOT sync here to avoid a third concurrent call.
                alarmService.stopBackgroundMonitoring()
                alarmService.cancelReengagementNotification()
            } else if newPhase == .background {
                if alarmService.activeAlarm != nil {
                    // Mid-alarm backgrounding: post re-engagement notification
                    alarmService.scheduleReengagementNotification()
                } else {
                    // Normal background: arm the silent keep-alive + timer
                    // so the next alarm fires even while the app is backgrounded
                    let enabledAlarms = alarms.filter { $0.isEnabled }
                    alarmService.startBackgroundMonitoring(alarms: enabledAlarms)
                }
            }
        }
    }
}

// MARK: - Main tab bar

struct MainTabView: View {
    @Bindable var router: NavigationRouter

    enum Tab { case home, stats, packs, bible, settings }

    var body: some View {
        TabView(selection: $router.selectedTab) {
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
