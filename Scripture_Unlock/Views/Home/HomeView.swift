import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext)       private var context
    @Environment(AlarmService.self)    private var alarmService
    @Environment(SupabaseService.self) private var supabase
    @Environment(NavigationRouter.self) private var router
    @Query(sort: \Alarm.createdAt) private var alarms: [Alarm]
    @Query private var profiles: [UserProfile]
    @Query private var streaks: [StreakEntry]
    @State private var vm             = AlarmListViewModel()
    @State private var showingNewAlarm  = false
    @State private var editingAlarm: Alarm? = nil
    @State private var now            = Date()
    @State private var votd:          VerseOfDay? = nil
    @State private var votdPlayer     = VersOfDayAudioPlayer()

    private var profile: UserProfile? { profiles.first }

    private var currentStreak: Int {
        var count = 0
        var date = Calendar.current.startOfDay(for: Date())
        while streaks.contains(where: {
            Calendar.current.isDate($0.date, inSameDayAs: date) && $0.dismissedAt != nil
        }) {
            count += 1
            date = Calendar.current.date(byAdding: .day, value: -1, to: date)!
        }
        return count
    }

    private var greetingWord: String {
        let hour = Calendar.current.component(.hour, from: now)
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default:     return "Good evening"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroStrip
                        .padding(.bottom, 20)

                    VerseCard(
                        reference:    votd?.ref         ?? "Psalm 5:3",
                        text:         votd?.text        ?? "O Lord, in the morning you hear my voice; in the morning I prepare a sacrifice for you and watch.",
                        translation:  votd?.translation ?? "NIV",
                        audioStatus:  votd?.audioStatus,
                        isPlaying:    votdPlayer.isPlaying,
                        isGenerating: votdPlayer.isGenerating,
                        onPlayAudio:  votd?.audioStatus != nil && votd?.audioStatus != "failed" ? {
                            if votd?.audioStatus == "ready" {
                                votdPlayer.togglePlayPause()
                            } else {
                                votdPlayer.requestAndPlay { fresh in votd = fresh }
                            }
                        } : nil
                    )
                    .padding(.horizontal, 20)
                    .contextMenu {
                        if let v = votd {
                            Button {
                                // Switch tab first so BibleView is visible and
                                // its NavigationStack is ready, THEN fire the
                                // deep link so onChange has a live view to act on.
                                router.selectedTab = .bible
                                let link = BibleDeepLink(
                                    book:     v.book,
                                    bookName: v.ref.components(separatedBy: " ").dropLast().joined(separator: " "),
                                    chapter:  v.chapter,
                                    verse:    v.verse
                                )
                                Task {
                                    try? await Task.sleep(for: .milliseconds(450))
                                    router.bibleDeepLink = link
                                }
                            } label: {
                                Label("Go to verse", systemImage: "book.pages")
                            }
                            Button {
                                UIPasteboard.general.string = "\(v.ref) (NIV)\n\"\(v.text)\""
                            } label: {
                                Label("Copy verse", systemImage: "doc.on.doc")
                            }
                        }
                    }
                    .task {
                        // Always re-fetch — never serve a cached verse/audio_url
                        votd = await VerseOfDayService.shared.today()
                        if let url = votd?.audioURL {
                            votdPlayer.load(url: url)
                        }
                    }

                    alarmSection
                        .padding(.top, 28)

                    if profile?.sabbathModeEnabled == true {
                        sabbathBanner
                            .padding(.horizontal, 20)
                            .padding(.top, 18)
                    }

                    Spacer(minLength: 40)
                }
            }
            .background(DesignSystem.warmCream.ignoresSafeArea())
            .navigationTitle("Scripture Unlock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // Dev-only: fire alarm immediately to test the full trivia flow
                    Button {
                        let testAlarm = alarms.first ?? Alarm(label: "Test", hour: 6, minute: 0)
                        alarmService.activeAlarm = testAlarm
                        alarmService.startAlarmAudio()
                    } label: {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(DesignSystem.pastoralGold)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingNewAlarm = true } label: {
                        ZStack {
                            Circle()
                                .fill(DesignSystem.deepBlue)
                                .frame(width: 32, height: 32)
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            // New alarm
            .sheet(isPresented: $showingNewAlarm) {
                SetAlarmView(alarm: Alarm(), isNew: true)
            }
            // Edit existing alarm — driven by editingAlarm binding
            .sheet(item: $editingAlarm) { alarm in
                SetAlarmView(alarm: alarm, isNew: false)
            }
        }
        .onAppear { now = Date() }
    }

    // MARK: - Hero strip

    private var heroStrip: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(hex: "0D1B3E"), Color(hex: "1E3A5F")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [DesignSystem.pastoralGold.opacity(0.18), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 300
            )

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.5))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(greetingWord + ",")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                        Text(profile?.name ?? "friend")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(DesignSystem.pastoralGold)
                    }

                    if currentStreak > 0 { streakPill.padding(.top, 4) }
                }

                Spacer()
                GoldSeal(size: 52)
                    .shadow(color: DesignSystem.pastoralGold.opacity(0.4), radius: 16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
    }

    private var streakPill: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .foregroundStyle(DesignSystem.pastoralGold)
                .font(.system(size: 12))
            Text("\(currentStreak)-day streak")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DesignSystem.pastoralGold)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(DesignSystem.pastoralGold.opacity(0.16))
        .overlay(Capsule().stroke(DesignSystem.pastoralGold.opacity(0.3), lineWidth: 0.5))
        .clipShape(Capsule())
    }

    // MARK: - Alarm section

    private var alarmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Your alarms").padding(.horizontal, 20)
                Spacer()
                if !alarms.isEmpty {
                    Button { showingNewAlarm = true } label: {
                        Text("Add")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DesignSystem.royalBlue)
                    }
                    .padding(.trailing, 20)
                }
            }

            if alarms.isEmpty {
                emptyAlarmState
            } else {
                VStack(spacing: 0) {
                    ForEach(alarms) { alarm in
                        AlarmRowView(alarm: alarm) {
                            vm.toggle(alarm)
                        }
                        // ── Tap to edit ──────────────────────────────────────
                        .contentShape(Rectangle())
                        .onTapGesture { editingAlarm = alarm }
                        // ── Long-press context menu ──────────────────────────
                        .contextMenu {
                            Button {
                                editingAlarm = alarm
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }

                            Button {
                                duplicateAlarm(alarm)
                            } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }

                            Divider()

                            Button(role: .destructive) {
                                vm.delete(alarm, context: context)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        // ── Swipe to delete ──────────────────────────────────
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                vm.delete(alarm, context: context)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        // ── Swipe to edit (leading) ──────────────────────────
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                editingAlarm = alarm
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(DesignSystem.royalBlue)

                            Button {
                                duplicateAlarm(alarm)
                            } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            .tint(DesignSystem.bethanyGreen)
                        }

                        if alarm.id != alarms.last?.id {
                            Divider().padding(.leading, 72)
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

    // MARK: - Empty state

    private var emptyAlarmState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(DesignSystem.pastoralGold.opacity(0.08))
                    .frame(width: 72, height: 72)
                Image(systemName: "alarm")
                    .font(.system(size: 30))
                    .foregroundStyle(DesignSystem.pastoralGold.opacity(0.6))
            }
            VStack(spacing: 6) {
                Text("No alarms yet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DesignSystem.ink)
                Text("Set your first Scripture Alarm\nand start your morning devotional habit.")
                    .font(.system(size: 13))
                    .foregroundStyle(DesignSystem.slate400)
                    .multilineTextAlignment(.center)
            }
            Button { showingNewAlarm = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                    Text("Set an alarm").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(DesignSystem.deepBlue)
                .cornerRadius(12)
            }
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sabbath banner

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

    // MARK: - Actions

    private func duplicateAlarm(_ original: Alarm) {
        let copy = Alarm()
        copy.hour          = original.hour
        copy.minute        = original.minute
        copy.isAM          = original.isAM
        copy.label         = original.label.isEmpty ? "" : "\(original.label) (copy)"
        copy.repeatDays    = original.repeatDays
        copy.packId        = original.packId
        copy.questionCount = original.questionCount
        copy.difficulty    = original.difficulty
        copy.translation   = original.translation
        copy.isEnabled     = false   // start disabled so it doesn't fire unexpectedly
        context.insert(copy)
        Task { await supabase.upsertAlarm(copy) }
    }
}
