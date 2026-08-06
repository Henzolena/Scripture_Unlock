import SwiftUI
import SwiftData
import Auth   // for session.accessToken

/// Hosts the trivia state machine — routes between MCQ, Fill, Reveal, Dismissed.
struct TriviaContainerView: View {
    let alarm: Alarm
    @State private var vm: TriviaViewModel
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var context
    @Environment(SupabaseService.self)  private var supabase

    private var parallelLanguage: String { profiles.first?.parallelLanguage ?? "" }

    init(alarm: Alarm) {
        self.alarm = alarm
        _vm = State(initialValue: TriviaViewModel(alarm: alarm))
    }

    var body: some View {
        ZStack {
            switch vm.phase {
            case .ringing:
                // begin() is driven by the container's own onAppear below. Calling
                // it from here as well double-invoked it and burned a cached question.
                Color(DesignSystem.warmCream).ignoresSafeArea()

            case .question:
                questionView
                    .background(DesignSystem.warmCream.ignoresSafeArea())
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))

            case .correctMoment(let step):
                if let q = vm.currentQuestion {
                    CorrectMomentView(
                        question:      q,
                        completedStep: step,
                        totalSteps:    vm.totalSteps,
                        onContinue:    { vm.continueFromMoment() }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal:   .opacity
                    ))
                }

            case .reveal:
                if let q = vm.currentQuestion {
                    RevealView(question: q, vm: vm)
                        .background(DesignSystem.warmCream.ignoresSafeArea())
                        .transition(.opacity)
                }

            case .dismissed:
                DismissedView(alarm: alarm)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.28), value: vm.phase)
        .onAppear { if vm.phase == .ringing { vm.begin(language: parallelLanguage) } }
        .onChange(of: vm.phase) { _, newPhase in
            if case .dismissed = newPhase { saveStreakEntry() }
        }
    }

    // MARK: - Streak persistence

    /// Called once when the alarm is successfully dismissed.
    /// Creates or updates today's StreakEntry and pushes it to Supabase.
    private func saveStreakEntry() {
        let today = Calendar.current.startOfDay(for: Date())
        let allEntries = (try? context.fetch(FetchDescriptor<StreakEntry>())) ?? []
        let existing = allEntries.first {
            Calendar.current.isDate($0.date, inSameDayAs: today)
        }

        let entry = existing ?? {
            let e = StreakEntry(date: today)
            context.insert(e)
            return e
        }()

        entry.questionsAnswered += vm.totalAttempts
        entry.questionsCorrect  += vm.completedSteps
        // Read the value captured at dismiss time — alarm.snoozeCountToday is
        // concurrently reset to zero by dismissAlarm().
        entry.snoozeCount       += vm.snoozeCountAtDismiss

        // Only a finished session counts. Previously dismissedAt was stamped
        // whenever this screen closed, so bailing out — via the escape hatch or
        // by silencing the alarm with questions left — scored exactly the same as
        // answering everything, and get_friends_leaderboard counts
        // dismissed_at IS NOT NULL as a completed session.
        let completed = vm.completedSteps >= vm.totalSteps
        if completed {
            entry.dismissedAt = Date()
        } else {
            entry.abandonedAt = Date()
        }

        Task { await supabase.upsertStreakEntry(entry) }

        if !completed { notifyAccountabilityPartner(entry: entry) }
    }

    /// Tells the accountability partner the morning was abandoned.
    ///
    /// Opt-in by construction: it only sends when the user has actually set a
    /// partner email. This is the part that gives up-and-quitting a real cost —
    /// iOS will always allow the alarm to be stopped, so social accountability
    /// does the work that force cannot.
    private func notifyAccountabilityPartner(entry: StreakEntry) {
        guard let profile = profiles.first else { return }
        let partner = profile.accountabilityPartnerEmail.trimmingCharacters(in: .whitespaces)
        guard !partner.isEmpty else { return }

        let host    = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_HOST") as? String ?? ""
        let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
        guard let url = URL(string: "https://\(host)/functions/v1/accountability-email") else { return }

        let payload: [String: Any] = [
            "name":          profile.name.isEmpty ? "Your friend" : profile.name,
            "partnerEmail":  partner,
            "streak":        vm.completedSteps,
            "accuracy":      entry.accuracy,
            "totalAnswered": entry.questionsAnswered
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        Task {
            guard let session = try? await SupabaseService.shared.currentSession() else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.httpBody   = body
            req.setValue(anonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    @ViewBuilder
    private var questionView: some View {
        if let q = vm.currentQuestion {
            VStack(spacing: 0) {
                TriviaProgressBar(
                    total: vm.totalSteps,
                    completed: vm.completedSteps,
                    ringing: true
                )
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 0)

                if let missed = vm.lastMissedQuestion {
                    MissBanner(missed: missed)
                        .padding(.horizontal, 24)
                        .padding(.top, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                ScrollView {
                    switch q.kind {
                    case .mcq:
                        MCQView(question: q, vm: vm)
                    case .fill:
                        FillView(question: q, vm: vm)
                    }
                }
            }
        } else if vm.isGeneratingQuestions {
            generatingView
        } else {
            // Previously there was no branch here at all: when no question could be
            // produced the screen rendered empty while the alarm kept ringing, with
            // the overlay deliberately un-dismissable. Always show something the
            // user can act on.
            unavailableView
        }
    }

    /// Shown when every question source has failed. Offers a retry and, as a last
    /// resort, a way to stop the alarm — being unable to silence it is worse than
    /// skipping the devotion.
    private var unavailableView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(DesignSystem.pastoralGold)

            VStack(spacing: 8) {
                Text("Couldn't load a question")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(DesignSystem.ink)
                Text("You may be offline. Try again, or silence the alarm and pick this up later.")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignSystem.slate600)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    vm.retryQuestionLoad()
                } label: {
                    Text("Try again")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(DesignSystem.deepBlue)
                        .cornerRadius(14)
                }

                if vm.questionSourcesExhausted {
                    Button {
                        vm.forceSilenceAfterFailure()
                    } label: {
                        Text("Silence alarm")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DesignSystem.slate600)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                }
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Shown when the AI question cache is empty and generation is in progress.
    private var generatingView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
                .tint(DesignSystem.deepBlue)
            VStack(spacing: 8) {
                Text("Preparing your questions…")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DesignSystem.ink)
                Text("Personalised Bible trivia is being generated.\nThis only takes a moment.")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignSystem.slate600)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - MissBanner

struct MissBanner: View {
    let missed: TriviaQuestion

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(DesignSystem.danger.opacity(0.10))
                    .frame(width: 30, height: 30)
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DesignSystem.danger)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text({
                    var base = AttributedString("Not quite — answer was ")
                    base.swiftUI.font           = .system(size: 13, weight: .bold)
                    base.swiftUI.foregroundColor = DesignSystem.ink
                    var answer = AttributedString(missed.correctAnswer)
                    answer.swiftUI.font           = .system(size: 13, weight: .bold)
                    answer.swiftUI.foregroundColor = DesignSystem.bethanyGreen
                    return base + answer
                }())

                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .bold))
                    Text("New verse · different book")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(DesignSystem.pastoralGold)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.surface)
        .cornerRadius(12)
        .shadow(color: DesignSystem.shadow1, radius: 6, x: 0, y: 2)
    }
}
