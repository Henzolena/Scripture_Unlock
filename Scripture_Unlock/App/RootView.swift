import SwiftUI
import SwiftData

/// Root navigator — decides between Onboarding and the main app.
/// Also intercepts when AlarmService fires an alarm mid-use.
struct RootView: View {
    @Environment(AlarmService.self)      private var alarmService
    @Environment(SupabaseService.self)   private var supabase
    @Environment(AchievementService.self) private var achievements
    @Environment(\.modelContext)         private var context
    @Environment(\.scenePhase)           private var scenePhase
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
        ZStack(alignment: .bottom) {
            Group {
                if profiles.isEmpty {
                    OnboardingFlow()
                } else {
                    ZStack {
                        MainTabView(router: router)

                        // Alarm overlay — sits directly in the view hierarchy so
                        // it cannot be dismissed by swipe, sheet gesture, or iOS
                        // background/foreground transitions. Only dismissed when
                        // TriviaViewModel.silenceAlarm() sets activeAlarm = nil.
                        if let alarm = alarmService.activeAlarm {
                            RingingView(alarm: alarm)
                                .ignoresSafeArea()
                                .transition(.opacity)
                                .zIndex(100)
                        }
                    }
                }
            }

            AppToastView()
        }
        .environment(router)
        .preferredColorScheme(preferredColorScheme)
        // One-time startup: reschedule saved alarms for this device.
        // Also run the AlarmKit check here because on cold launch the @Query
        // alarms array may still be empty when scenePhase fires .active.
        .task {
            // Let AlarmService resolve notification payloads back to the live
            // SwiftData object instead of rebuilding a detached copy that loses
            // repeatDays and the snooze question penalty.
            alarmService.alarmResolver = { [context] id in
                let all = (try? context.fetch(FetchDescriptor<Alarm>())) ?? []
                return all.first { $0.id == id }
            }

            let savedAlarms = (try? context.fetch(FetchDescriptor<Alarm>())) ?? []
            await alarmService.rescheduleAll(savedAlarms)
            if #available(iOS 26, *) {
                alarmService.checkPendingAlarmKitAlarm(alarms: savedAlarms)
            }
        }
        // Ask for notification permission only once the user has a profile, so the
        // system dialog lands after onboarding has explained why an alarm app needs
        // it. Requesting from AlarmService.init() fired it during cold launch.
        .task(id: profiles.isEmpty) {
            guard !profiles.isEmpty else { return }
            await alarmService.requestPermissions()
        }
        // Safety net: retry when SwiftData finishes loading the alarms query
        .onChange(of: alarms) { _, loaded in
            guard !loaded.isEmpty else { return }
            if #available(iOS 26, *) {
                alarmService.checkPendingAlarmKitAlarm(alarms: loaded)
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
                // Process AlarmKit events FIRST — snooze handling may clear activeAlarm,
                // in which case we must NOT restart audio (brief blip otherwise).
                if #available(iOS 26, *) {
                    alarmService.checkPendingAlarmKitAlarm(alarms: alarms)
                }
                // Re-start audio only if an alarm is still active after AlarmKit processing
                // (e.g. user backgrounded mid-quiz before the 0.5 s delay fired).
                alarmService.restartAlarmAudioIfNeeded()
            } else if newPhase == .background {
                if let active = alarmService.activeAlarm {
                    // Mid-alarm backgrounding: post re-engagement notification.
                    alarmService.scheduleReengagementNotification()
                    // activeAlarm is only non-nil while the quiz is unfinished —
                    // dismissAlarm() clears it on completion — so walking away here
                    // means the devotion was abandoned. Re-arm on a bounded ladder
                    // so going back to sleep does not work.
                    alarmService.escalateUnresolvedAlarm(active)
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
                Color.clear.frame(height: 110)
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
