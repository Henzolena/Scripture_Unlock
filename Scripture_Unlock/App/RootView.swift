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
        // One-time startup: reschedule saved alarms for this device.
        .task {
            let savedAlarms = (try? context.fetch(FetchDescriptor<Alarm>())) ?? []
            await alarmService.rescheduleAll(savedAlarms)
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

    enum Tab: Hashable { case home, stats, packs, community, bible, settings }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                tabPage(.home) { HomeView() }
                tabPage(.stats) { StatsView() }
                tabPage(.packs) { PacksView() }
                tabPage(.community) { CommunityView() }
                tabPage(.bible) { BibleView() }
                tabPage(.settings) { SettingsView() }
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 92)
            }

            AppBottomTabBar(selectedTab: Binding(
                get: { router.selectedTab },
                set: { router.selectedTab = $0 }
            ))
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .background(DesignSystem.warmCream.ignoresSafeArea())
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    @ViewBuilder
    private func tabPage<Content: View>(_ tab: Tab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(router.selectedTab == tab ? 1 : 0)
            .allowsHitTesting(router.selectedTab == tab)
            .accessibilityHidden(router.selectedTab != tab)
    }
}

private struct AppBottomTabBar: View {
    @Binding var selectedTab: MainTabView.Tab

    private let items: [TabItem] = [
        .init(tab: .home, label: "Alarms", icon: "alarm.fill"),
        .init(tab: .stats, label: "Streak", icon: "flame.fill"),
        .init(tab: .packs, label: "Verses", icon: "book.fill"),
        .init(tab: .community, label: "Friends", icon: "person.2.fill"),
        .init(tab: .bible, label: "Bible", icon: "books.vertical.fill"),
        .init(tab: .settings, label: "More", icon: "ellipsis")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selectedTab = item.tab
                    }
                } label: {
                    let isSelected = selectedTab == item.tab
                    VStack(spacing: 5) {
                        Image(systemName: item.icon)
                            .font(.system(size: item.tab == .settings ? 19 : 21, weight: .bold))
                            .frame(height: 23)
                        Text(item.label)
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isSelected ? DesignSystem.royalBlue : DesignSystem.slate700)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        RoundedRectangle(cornerRadius: 22)
                            .fill(isSelected ? DesignSystem.royalBlue.opacity(0.16) : .clear)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 30)
                .fill(DesignSystem.surface.opacity(0.96))
                .shadow(color: DesignSystem.shadow1, radius: 16, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .stroke(DesignSystem.royalBlue.opacity(0.18), lineWidth: 1)
        )
    }

    private struct TabItem: Identifiable {
        let tab: MainTabView.Tab
        let label: String
        let icon: String

        var id: MainTabView.Tab { tab }
    }
}
