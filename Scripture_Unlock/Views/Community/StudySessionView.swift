import Foundation
import SwiftUI

struct StudySessionView: View {
    @State private var live: StudySessionRealtimeService
    @State private var selectedPanel: Panel = .chat
    @State private var showingEndConfirm = false
    @State private var quizDurationSeconds = 90
    @FocusState private var messageFocused: Bool

    private enum Panel: String, CaseIterable {
        case chat = "Chat"
        case notes = "Notes"
    }

    init(sessionId: String) {
        _live = State(initialValue: StudySessionRealtimeService(sessionId: sessionId))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sessionHeader
                    phaseGuide
                    focusCard
                    reactionBar
                    panelPicker

                    if selectedPanel == .chat {
                        chatPanel
                    } else {
                        notesPanel
                    }
                }
                .padding(20)
                .padding(.bottom, 18)
            }
            .background(DesignSystem.warmCream.ignoresSafeArea())
            .navigationTitle(live.snapshot?.room.name ?? "Study")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            Task { await live.refresh() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }

                        if live.canLead {
                            Button(role: .destructive) {
                                showingEndConfirm = true
                            } label: {
                                Label("End Session", systemImage: "stop.circle.fill")
                            }
                    }
                } label: {
                    ToolbarIconLabel(systemName: "ellipsis", style: .secondary)
                }
            }
            }
            .task {
                await live.start()
            }
            .onDisappear {
                Task { await live.stop() }
            }
            .onChange(of: live.snapshot?.messages.count ?? 0) { _, _ in
                if let last = live.snapshot?.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            .alert("End this study session?", isPresented: $showingEndConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("End", role: .destructive) {
                    Task { await live.endSession() }
                }
            } message: {
                Text("Friends will still see the room, but this live session will be marked ended.")
            }
            .onChange(of: live.snapshot?.session.quizDurationSeconds ?? 90) { _, newValue in
                quizDurationSeconds = newValue
            }
        }
    }

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(live.isConnected ? DesignSystem.bethanyGreen : DesignSystem.slate400)
                            .frame(width: 8, height: 8)
                        Text(live.statusMessage)
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.1)
                            .textCase(.uppercase)
                            .foregroundStyle(DesignSystem.slate600)
                    }

                    Text(live.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(DesignSystem.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(live.reference)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DesignSystem.royalBlue)

                    if let role = live.snapshot?.room.myRole {
                        Text(roleTitle(role))
                            .font(.system(size: 10, weight: .black))
                            .tracking(0.9)
                            .textCase(.uppercase)
                            .foregroundStyle(roleColor(role))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(roleColor(role).opacity(0.10))
                            .cornerRadius(8)
                    }
                }

                Spacer()

                if live.isLoading {
                    ProgressView()
                        .tint(DesignSystem.royalBlue)
                }
            }

            if !live.onlineMembers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(live.onlineMembers) { member in
                            HStack(spacing: 7) {
                                AvatarCircle(name: member.name, size: 28)
                                Text(member.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(DesignSystem.ink)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(DesignSystem.surface)
                            .cornerRadius(14)
                        }
                    }
                }
            }
        }
        .padding(16)
        .cardStyle()
    }

    private var phaseGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Guide")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(studyPhases) { phase in
                        Button {
                            Task { await live.moveToPhase(phase.id) }
                        } label: {
                            VStack(spacing: 7) {
                                Image(systemName: phase.icon)
                                    .font(.system(size: 15, weight: .bold))
                                Text(phase.title)
                                    .font(.system(size: 11, weight: .bold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(live.phase == phase.id ? .white : DesignSystem.royalBlue)
                            .frame(width: 78, height: 62)
                            .background(live.phase == phase.id ? DesignSystem.deepBlue : DesignSystem.royalBlue.opacity(0.09))
                            .cornerRadius(14)
                        }
                        .buttonStyle(.plain)
                        .disabled(!live.canLead)
                        .opacity(live.canLead || live.phase == phase.id ? 1 : 0.55)
                    }
                }
            }

            if let snapshot = live.snapshot, let guide = snapshot.session.guide {
                GuidePhaseContent(
                    phase: live.phase,
                    guide: guide,
                    snapshot: snapshot,
                    canLead: live.canLead,
                    durationSeconds: $quizDurationSeconds,
                    onConfigureQuiz: { mode, duration in
                        Task { await live.configureQuiz(mode: mode, durationSeconds: duration) }
                    },
                    onStartTimedQuiz: { duration in
                        Task { await live.startTimedQuiz(durationSeconds: duration) }
                    },
                    onEndTimedQuiz: {
                        Task { await live.endTimedQuiz() }
                    },
                    onSubmitAnswer: { questionIndex, selectedIndex in
                        Task { await live.submitQuizAnswer(questionIndex: questionIndex, selectedIndex: selectedIndex) }
                    }
                )
            } else if live.isGeneratingGuide {
                GuideStatusCard(
                    title: "Preparing guide",
                    message: live.guideMessage.isEmpty ? "Building this session from the selected passage." : live.guideMessage,
                    showsProgress: true
                )
            } else if live.snapshot?.session.guideStatus == "failed" {
                GuideStatusCard(
                    title: "Guide unavailable",
                    message: live.guideMessage.isEmpty ? "The prepared study guide could not be generated for this session." : live.guideMessage,
                    showsProgress: false
                )
            } else {
                GuideStatusCard(
                    title: "Preparing guide",
                    message: "The selected passage will appear here as a complete session guide.",
                    showsProgress: false
                )
            }
        }
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Scripture Focus", systemImage: "book.fill")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(DesignSystem.pastoralGold)
                Spacer()
                languageBadge(live.snapshot?.session.language ?? "en")
            }

            Text(live.reference)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(DesignSystem.ink)

            if let verse = live.focusVerseText, !verse.isEmpty {
                Text("\"\(verse)\"")
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(DesignSystem.slate700)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Read the selected passage together, then move through reflection, discussion, quiz, prayer, and recap.")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignSystem.slate600)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .cardStyle()
    }

    private var reactionBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Reactions")

            HStack(spacing: 8) {
                ForEach(reactionOptions) { reaction in
                    let isSelected = live.snapshot?.myReactions.contains(reaction.id) == true
                    Button {
                        Task { await live.react(reaction.id) }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: reaction.icon)
                                .font(.system(size: 15, weight: .bold))
                            Text("\(live.snapshot?.reactionCounts[reaction.id] ?? 0)")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(isSelected ? .white : DesignSystem.royalBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isSelected ? DesignSystem.royalBlue : DesignSystem.royalBlue.opacity(0.08))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(reaction.title)
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                }
            }
        }
    }

    private var panelPicker: some View {
        HStack(spacing: 6) {
            ForEach(Panel.allCases, id: \.self) { panel in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedPanel = panel
                    }
                } label: {
                    Text(panel.rawValue)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(selectedPanel == panel ? .white : DesignSystem.slate600)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedPanel == panel ? DesignSystem.deepBlue : DesignSystem.surface)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var chatPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if live.snapshot?.messages.isEmpty != false {
                emptyState("No messages yet.", icon: "bubble.left.and.bubble.right")
            } else {
                VStack(spacing: 10) {
                    ForEach(live.snapshot?.messages ?? []) { message in
                        MessageRow(message: message, isMine: message.userId == live.currentUserId)
                            .id(message.id)
                    }
                }
            }

            HStack(spacing: 10) {
                TextField("Share an insight or prayer", text: $live.messageDraft, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.system(size: 14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(DesignSystem.surface)
                    .cornerRadius(12)
                    .focused($messageFocused)

                AppIconButton(
                    systemName: "paperplane.fill",
                    style: live.messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .neutral : .primary,
                    size: 42,
                    disabled: live.messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    Task {
                        await live.sendMessage()
                        messageFocused = false
                    }
                }
            }
        }
    }

    private var notesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Capture a shared note", text: $live.noteDraft, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.system(size: 14))
                    .padding(12)
                    .background(DesignSystem.surface)
                    .cornerRadius(12)

                AppActionButton(
                    title: "Save Note",
                    icon: "square.and.pencil",
                    disabled: live.noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    Task { await live.saveNote() }
                }
            }

            if live.snapshot?.notes.isEmpty != false {
                emptyState("No shared notes yet.", icon: "note.text")
            } else {
                VStack(spacing: 10) {
                    ForEach(live.snapshot?.notes ?? []) { note in
                        NoteRow(note: note)
                    }
                }
            }
        }
    }

    private var activePhase: StudyPhase {
        studyPhases.first { $0.id == live.phase } ?? studyPhases[0]
    }

    private func languageBadge(_ language: String) -> some View {
        Text(languageLabel(language))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(DesignSystem.royalBlue)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(DesignSystem.royalBlue.opacity(0.09))
            .cornerRadius(9)
    }

    private func emptyState(_ text: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignSystem.slate400)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DesignSystem.slate600)
            Spacer()
        }
        .padding(14)
        .cardStyle()
    }

    private func roleTitle(_ role: String) -> String {
        switch role {
        case "owner": return "Owner"
        case "admin": return "Admin"
        case "leader": return "Leader"
        default: return "Member"
        }
    }

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "owner": return DesignSystem.pastoralGold
        case "admin": return DesignSystem.deepBlue
        case "leader": return DesignSystem.bethanyGreen
        default: return DesignSystem.slate600
        }
    }
}

private struct GuideStatusCard: View {
    let title: String
    let message: String
    let showsProgress: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showsProgress {
                ProgressView()
                    .tint(DesignSystem.royalBlue)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DesignSystem.pastoralGold)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DesignSystem.ink)
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.slate600)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .cardStyle()
    }
}

private struct GuidePhaseContent: View {
    let phase: String
    let guide: PreparedStudyGuide
    let snapshot: StudySessionSnapshot
    let canLead: Bool
    @Binding var durationSeconds: Int
    let onConfigureQuiz: (String, Int) -> Void
    let onStartTimedQuiz: (Int) -> Void
    let onEndTimedQuiz: () -> Void
    let onSubmitAnswer: (Int, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch phase {
            case "reflect":
                GuideTextBlock(title: "Devotional", text: guide.reflect.devotional)
                GuideListBlock(title: "Reflect", items: guide.reflect.personalQuestions, icon: "lightbulb.fill")
                GuideTextBlock(title: "Apply", text: guide.reflect.application)
            case "discuss":
                GuideTextBlock(title: "Opening", text: guide.discuss.openingQuestion)
                GuideListBlock(title: "Questions", items: guide.discuss.discussionQuestions, icon: "bubble.left.fill")
                if !guide.discuss.leaderNotes.isEmpty {
                    GuideListBlock(title: "Leader Notes", items: guide.discuss.leaderNotes, icon: "person.2.fill")
                }
            case "quiz":
                QuizPhaseContent(
                    guide: guide,
                    snapshot: snapshot,
                    canLead: canLead,
                    durationSeconds: $durationSeconds,
                    onConfigureQuiz: onConfigureQuiz,
                    onStartTimedQuiz: onStartTimedQuiz,
                    onEndTimedQuiz: onEndTimedQuiz,
                    onSubmitAnswer: onSubmitAnswer
                )
            case "pray":
                GuideListBlock(title: "Prayer Points", items: guide.pray.prayerPoints, icon: "hands.clap.fill")
                GuideTextBlock(title: "Guided Prayer", text: guide.pray.guidedPrayer)
            case "recap":
                GuideTextBlock(title: "Takeaway", text: guide.recap.mainTakeaway)
                GuideTextBlock(title: "Memory Phrase", text: guide.recap.memoryPhrase)
                GuideTextBlock(title: "Next Step", text: guide.recap.nextStep)
                GuideTextBlock(title: "Closing", text: guide.recap.closingSummary)
            default:
                GuideTextBlock(title: "Summary", text: guide.read.summary)
                GuideTextBlock(title: "Context", text: guide.read.context)
                GuideListBlock(title: "Observe", items: guide.read.keyObservations, icon: "eye.fill")
                if !guide.read.keyTerms.isEmpty {
                    GuideTermsBlock(terms: guide.read.keyTerms)
                }
            }
        }
        .padding(14)
        .cardStyle()
    }
}

private struct QuizPhaseContent: View {
    let guide: PreparedStudyGuide
    let snapshot: StudySessionSnapshot
    let canLead: Bool
    @Binding var durationSeconds: Int
    let onConfigureQuiz: (String, Int) -> Void
    let onStartTimedQuiz: (Int) -> Void
    let onEndTimedQuiz: () -> Void
    let onSubmitAnswer: (Int, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if canLead {
                LeaderQuizControls(
                    snapshot: snapshot,
                    durationSeconds: $durationSeconds,
                    onConfigureQuiz: onConfigureQuiz,
                    onStartTimedQuiz: onStartTimedQuiz,
                    onEndTimedQuiz: onEndTimedQuiz
                )
            }

            if snapshot.session.quizMode == "timed" {
                timedQuizContent
            } else {
                GuideTextBlock(
                    title: "Leader-Led Quiz",
                    text: canLead
                        ? "Use these prepared questions to guide the group. Members see the questions and choices, but answer keys stay leader-only."
                        : "Answer keys are hidden while your leader guides the group through these questions."
                )

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(guide.quiz.questions.enumerated()), id: \.offset) { index, question in
                        GuideQuizQuestionCard(number: index + 1, question: question)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var timedQuizContent: some View {
        switch snapshot.session.quizStatus {
        case "running":
            TimedQuizStatusCard(snapshot: snapshot)
            TimedQuizQuestionList(
                guide: guide,
                snapshot: snapshot,
                onSubmitAnswer: onSubmitAnswer
            )
            if canLead {
                QuizResultsCard(snapshot: snapshot, isLive: true)
            }
        case "ended":
            TimedQuizStatusCard(snapshot: snapshot)
            TimedQuizQuestionList(
                guide: guide,
                snapshot: snapshot,
                onSubmitAnswer: onSubmitAnswer
            )
            QuizResultsCard(snapshot: snapshot, isLive: false)
        default:
            GuideTextBlock(
                title: "Timed Quiz",
                text: canLead
                    ? "Start the timed quiz when the group is ready. Answers and scores will post to the session when the quiz ends."
                    : "Your leader is preparing the timed quiz. Questions unlock when the timer starts."
            )

            if canLead {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(guide.quiz.questions.enumerated()), id: \.offset) { index, question in
                        GuideQuizQuestionCard(number: index + 1, question: question)
                    }
                }
            }
        }
    }
}

private struct LeaderQuizControls: View {
    let snapshot: StudySessionSnapshot
    @Binding var durationSeconds: Int
    let onConfigureQuiz: (String, Int) -> Void
    let onStartTimedQuiz: (Int) -> Void
    let onEndTimedQuiz: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Leader Controls")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(DesignSystem.pastoralGold)

            HStack(spacing: 8) {
                quizModeButton(title: "Question List", mode: "leader_led", icon: "list.bullet.clipboard")
                quizModeButton(title: "Timed", mode: "timed", icon: "timer")
            }

            if snapshot.session.quizMode == "timed" {
                HStack(spacing: 8) {
                    ForEach([60, 90, 120, 180], id: \.self) { seconds in
                        Button {
                            durationSeconds = seconds
                            onConfigureQuiz("timed", seconds)
                        } label: {
                            Text(durationLabel(seconds))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(durationSeconds == seconds ? .white : DesignSystem.royalBlue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(durationSeconds == seconds ? DesignSystem.royalBlue : DesignSystem.royalBlue.opacity(0.08))
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .disabled(snapshot.session.quizStatus == "running")
                    }
                }

                if snapshot.session.quizStatus == "running" {
                    AppActionButton(
                        title: "End Quiz & Post Results",
                        icon: "flag.checkered",
                        style: .success,
                        size: .compact
                    ) {
                        onEndTimedQuiz()
                    }
                } else {
                    AppActionButton(
                        title: "Start Timed Quiz",
                        icon: "play.fill",
                        size: .compact
                    ) {
                        onStartTimedQuiz(durationSeconds)
                    }
                }
            }
        }
        .padding(12)
        .background(DesignSystem.royalBlue.opacity(0.05))
        .cornerRadius(14)
    }

    private func quizModeButton(title: String, mode: String, icon: String) -> some View {
        Button {
            onConfigureQuiz(mode, durationSeconds)
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(snapshot.session.quizMode == mode ? .white : DesignSystem.royalBlue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(snapshot.session.quizMode == mode ? DesignSystem.deepBlue : DesignSystem.royalBlue.opacity(0.08))
                .cornerRadius(11)
        }
        .buttonStyle(.plain)
        .disabled(snapshot.session.quizStatus == "running")
    }

    private func durationLabel(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m"
    }
}

private struct TimedQuizStatusCard: View {
    let snapshot: StudySessionSnapshot

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = remainingSeconds(at: context.date)

            HStack(spacing: 12) {
                Image(systemName: snapshot.session.quizStatus == "ended" ? "checkmark.seal.fill" : "timer")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(snapshot.session.quizStatus == "ended" ? DesignSystem.bethanyGreen : DesignSystem.royalBlue)
                    .frame(width: 38, height: 38)
                    .background(DesignSystem.royalBlue.opacity(0.08))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle(remaining: remaining))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DesignSystem.ink)
                    Text(statusDetail(remaining: remaining))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignSystem.slate600)
                }

                Spacer()
            }
            .padding(12)
            .background(DesignSystem.surface)
            .cornerRadius(14)
        }
    }

    private func remainingSeconds(at date: Date) -> Int {
        guard snapshot.session.quizStatus == "running",
              let startedAt = parseSupabaseDate(snapshot.session.quizStartedAt) else {
            return 0
        }

        let end = startedAt.addingTimeInterval(TimeInterval(snapshot.session.quizDurationSeconds))
        return max(0, Int(end.timeIntervalSince(date).rounded(.up)))
    }

    private func statusTitle(remaining: Int) -> String {
        if snapshot.session.quizStatus == "ended" {
            return "Quiz Complete"
        }
        return remaining > 0 ? "Timed Quiz Running" : "Time Is Up"
    }

    private func statusDetail(remaining: Int) -> String {
        if snapshot.session.quizStatus == "ended" {
            return "Results are available to the group."
        }
        return "\(remaining / 60):\(String(format: "%02d", remaining % 60)) remaining"
    }
}

private struct TimedQuizQuestionList: View {
    let guide: PreparedStudyGuide
    let snapshot: StudySessionSnapshot
    let onSubmitAnswer: (Int, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(guide.quiz.questions.enumerated()), id: \.offset) { index, question in
                TimedQuizQuestionCard(
                    index: index,
                    question: question,
                    answer: answer(for: index),
                    isRunning: snapshot.session.quizStatus == "running",
                    onSubmitAnswer: onSubmitAnswer
                )
            }
        }
    }

    private func answer(for index: Int) -> StudySessionQuizAnswer? {
        snapshot.quiz.myAnswers.first { $0.questionIndex == index }
    }
}

private struct TimedQuizQuestionCard: View {
    let index: Int
    let question: StudyGuideQuizQuestion
    let answer: StudySessionQuizAnswer?
    let isRunning: Bool
    let onSubmitAnswer: (Int, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Question \(index + 1)")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(DesignSystem.pastoralGold)

            Text(question.question)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DesignSystem.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 7) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { optionIndex, option in
                    let isSelected = answer?.selectedIndex == optionIndex
                    let isCorrectOption = question.answerIndex == optionIndex && question.answerIndex >= 0
                    Button {
                        onSubmitAnswer(index, optionIndex)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Text(optionLabel(optionIndex))
                                .font(.system(size: 11, weight: .black))
                                .foregroundStyle((isSelected || isCorrectOption) ? .white : DesignSystem.royalBlue)
                                .frame(width: 22, height: 22)
                                .background(optionBadgeColor(isSelected: isSelected, isCorrectOption: isCorrectOption))
                                .clipShape(Circle())
                            Text(option)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(DesignSystem.slate700)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(optionBackground(isSelected: isSelected, isCorrectOption: isCorrectOption))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isRunning)
                }
            }

            if let answer {
                Text(answerStatus(answer))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(answer.isCorrect == false ? Color.red.opacity(0.82) : DesignSystem.bethanyGreen)
            }

            if question.answerIndex >= 0, !question.explanation.isEmpty {
                Text(question.explanation)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.slate600)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(DesignSystem.royalBlue.opacity(0.05))
        .cornerRadius(14)
    }

    private func answerStatus(_ answer: StudySessionQuizAnswer) -> String {
        if let isCorrect = answer.isCorrect {
            return isCorrect ? "Correct" : "Review after the quiz"
        }
        return "Submitted"
    }

    private func optionBadgeColor(isSelected: Bool, isCorrectOption: Bool) -> Color {
        if isCorrectOption { return DesignSystem.bethanyGreen }
        if isSelected { return DesignSystem.royalBlue }
        return DesignSystem.royalBlue.opacity(0.09)
    }

    private func optionBackground(isSelected: Bool, isCorrectOption: Bool) -> Color {
        if isCorrectOption { return DesignSystem.bethanyGreen.opacity(0.10) }
        if isSelected { return DesignSystem.royalBlue.opacity(0.10) }
        return DesignSystem.surface
    }

    private func optionLabel(_ index: Int) -> String {
        ["A", "B", "C", "D"].indices.contains(index) ? ["A", "B", "C", "D"][index] : "\(index + 1)"
    }
}

private struct QuizResultsCard: View {
    let snapshot: StudySessionSnapshot
    let isLive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isLive ? "Live Progress" : "Group Results")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(DesignSystem.pastoralGold)

            if snapshot.quiz.results.isEmpty {
                Text("No answers submitted yet.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.slate600)
            } else {
                ForEach(snapshot.quiz.results) { result in
                    HStack(spacing: 10) {
                        AvatarCircle(name: result.userName, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.userName)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(DesignSystem.ink)
                            Text(result.isComplete ? "Completed" : "\(result.answered)/\(max(result.total, 1)) answered")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DesignSystem.slate600)
                        }
                        Spacer()
                        Text("\(result.correct)/\(max(result.total, 1))")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(DesignSystem.royalBlue)
                    }
                    .padding(10)
                    .background(DesignSystem.surface)
                    .cornerRadius(12)
                }
            }
        }
        .padding(12)
        .background(DesignSystem.royalBlue.opacity(0.05))
        .cornerRadius(14)
    }
}

private struct GuideTextBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(DesignSystem.pastoralGold)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DesignSystem.slate700)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct GuideListBlock: View {
    let title: String
    let items: [String]
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(DesignSystem.pastoralGold)

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DesignSystem.royalBlue)
                        .frame(width: 18, height: 18)
                    Text(item)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DesignSystem.slate700)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct GuideTermsBlock: View {
    let terms: [StudyGuideTerm]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Key Terms")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(DesignSystem.pastoralGold)

            ForEach(terms) { term in
                VStack(alignment: .leading, spacing: 4) {
                    Text(term.term)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DesignSystem.ink)
                    Text(term.meaning)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DesignSystem.slate600)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignSystem.royalBlue.opacity(0.07))
                .cornerRadius(12)
            }
        }
    }
}

private struct GuideQuizQuestionCard: View {
    let number: Int
    let question: StudyGuideQuizQuestion

    var body: some View {
        let revealsAnswer = question.answerIndex >= 0

        VStack(alignment: .leading, spacing: 10) {
            Text("Question \(number)")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(DesignSystem.pastoralGold)

            Text(question.question)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DesignSystem.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 7) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    HStack(alignment: .top, spacing: 8) {
                        Text(optionLabel(index))
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(revealsAnswer && index == question.answerIndex ? .white : DesignSystem.royalBlue)
                            .frame(width: 22, height: 22)
                            .background(revealsAnswer && index == question.answerIndex ? DesignSystem.bethanyGreen : DesignSystem.royalBlue.opacity(0.09))
                            .clipShape(Circle())
                        Text(option)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DesignSystem.slate700)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(revealsAnswer && index == question.answerIndex ? DesignSystem.bethanyGreen.opacity(0.10) : DesignSystem.surface)
                    .cornerRadius(12)
                }
            }

            if revealsAnswer, !question.explanation.isEmpty {
                Text(question.explanation)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.slate600)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(DesignSystem.royalBlue.opacity(0.05))
        .cornerRadius(14)
    }

    private func optionLabel(_ index: Int) -> String {
        ["A", "B", "C", "D"].indices.contains(index) ? ["A", "B", "C", "D"][index] : "\(index + 1)"
    }
}

private struct StudyPhase: Identifiable {
    let id: String
    let title: String
    let icon: String
    let prompt: String
}

private let studyPhases: [StudyPhase] = [
    StudyPhase(id: "read", title: "Read", icon: "book.fill", prompt: "Read the passage aloud and notice repeated words, actions, and promises."),
    StudyPhase(id: "reflect", title: "Reflect", icon: "lightbulb.fill", prompt: "Each person names one phrase that stands out and why it matters today."),
    StudyPhase(id: "discuss", title: "Discuss", icon: "bubble.left.and.bubble.right.fill", prompt: "Ask what the passage reveals about God, people, faith, and obedience."),
    StudyPhase(id: "quiz", title: "Quiz", icon: "checkmark.seal.fill", prompt: "Recall the core detail without looking, then explain the answer from the text."),
    StudyPhase(id: "pray", title: "Pray", icon: "hands.clap.fill", prompt: "Turn the passage into a short prayer for your group and your day."),
    StudyPhase(id: "recap", title: "Recap", icon: "flag.checkered", prompt: "Write the group takeaway and one simple action before the next session.")
]

private struct ReactionOption: Identifiable {
    let id: String
    let title: String
    let icon: String
}

private let reactionOptions: [ReactionOption] = [
    ReactionOption(id: "amen", title: "Amen", icon: "checkmark.circle.fill"),
    ReactionOption(id: "insightful", title: "Insightful", icon: "lightbulb.fill"),
    ReactionOption(id: "praying", title: "Praying", icon: "hands.clap.fill"),
    ReactionOption(id: "question", title: "Question", icon: "questionmark.circle.fill"),
    ReactionOption(id: "heart", title: "Heart", icon: "heart.fill")
]

private struct MessageRow: View {
    let message: StudySessionMessage
    let isMine: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarCircle(name: message.userName, size: 34)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(message.userName.isEmpty ? "Friend" : message.userName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DesignSystem.ink)
                    if message.kind != "chat" {
                        Text(message.kind.capitalized)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(DesignSystem.pastoralGold)
                    }
                    Spacer()
                }
                Text(message.body)
                    .font(.system(size: 14))
                    .foregroundStyle(DesignSystem.slate700)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(isMine ? DesignSystem.royalBlue.opacity(0.08) : DesignSystem.surface)
            .cornerRadius(14)
        }
    }
}

private struct NoteRow: View {
    let note: StudySessionNote

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(note.userName.isEmpty ? "Friend" : note.userName, systemImage: "person.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DesignSystem.royalBlue)
                Spacer()
                if let ref = note.verseRef, !ref.isEmpty {
                    Text(ref)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DesignSystem.slate400)
                }
            }

            Text(note.body)
                .font(.system(size: 14))
                .foregroundStyle(DesignSystem.slate700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .cardStyle()
    }
}

private func parseSupabaseDate(_ value: String?) -> Date? {
    guard let value, !value.isEmpty else { return nil }

    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) {
        return date
    }

    let standard = ISO8601DateFormatter()
    standard.formatOptions = [.withInternetDateTime]
    return standard.date(from: value)
}

private func languageLabel(_ language: String) -> String {
    switch language {
    case "am": return "Amharic"
    case "or": return "Oromo"
    case "ti": return "Tigrigna"
    default: return "English"
    }
}
