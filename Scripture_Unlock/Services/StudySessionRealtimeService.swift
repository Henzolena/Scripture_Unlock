import Foundation
import Auth
import Realtime

struct StudyPresence: Codable, Hashable, Identifiable {
    let userId: String
    let name: String
    let phase: String
    let joinedAt: String

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case name, phase
        case userId = "user_id"
        case joinedAt = "joined_at"
    }
}

@MainActor
@Observable
final class StudySessionRealtimeService {
    let sessionId: String

    private let community = CommunityService.shared
    private let studyGuide = StudyGuideService.shared
    private let host: String
    private let anonKey: String
    private let isoFormatter = ISO8601DateFormatter()

    private var realtime: RealtimeClientV2?
    private var channel: RealtimeChannelV2?
    private var broadcastTask: Task<Void, Never>?
    private var presenceTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var guideGenerationTask: Task<Void, Never>?
    private var quizAutoEndTask: Task<Void, Never>?
    private var didStart = false
    private var onlineByUserId: [String: StudyPresence] = [:]
    private var attemptedGuideSessionIds: Set<String> = []
    private var focusVerseKey = ""
    private var scheduledQuizEndKey = ""

    private(set) var snapshot: StudySessionSnapshot?
    private(set) var onlineMembers: [StudyPresence] = []
    private(set) var focusVerseText: String?
    private(set) var currentUserId = ""
    private(set) var isLoading = false
    private(set) var isGeneratingGuide = false
    private(set) var isConnected = false
    private(set) var statusMessage = "Connecting..."
    private(set) var guideMessage = ""

    var messageDraft = ""
    var noteDraft = ""

    init(sessionId: String) {
        self.sessionId = sessionId
        host = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_HOST") as? String ?? ""
        anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
    }

    var phase: String {
        snapshot?.session.phase ?? "read"
    }

    var title: String {
        snapshot?.session.title ?? "Bible study"
    }

    var reference: String {
        snapshot?.session.reference ?? "Open study"
    }

    var canLead: Bool {
        snapshot?.room.canLead == true
    }

    var canManageRoles: Bool {
        snapshot?.room.canManageRoles == true
    }

    func start() async {
        guard !didStart else { return }
        didStart = true

        await loadSnapshot(showSpinner: true)
        await connect()
    }

    func stop() async {
        refreshTask?.cancel()
        broadcastTask?.cancel()
        presenceTask?.cancel()
        statusTask?.cancel()
        guideGenerationTask?.cancel()
        quizAutoEndTask?.cancel()

        if let channel {
            await channel.untrack()
            await channel.unsubscribe()
            await realtime?.removeChannel(channel)
        }

        realtime?.disconnect()
        realtime = nil
        channel = nil
        scheduledQuizEndKey = ""
        didStart = false
        isConnected = false
        statusMessage = "Disconnected"
    }

    func refresh() async {
        await loadSnapshot(showSpinner: false)
    }

    func sendMessage(kind: String = "chat") async {
        let body = messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }

        messageDraft = ""
        do {
            try await community.postMessage(sessionId: sessionId, body: body, kind: kind, verseRef: referenceForMutation)
            await loadSnapshot(showSpinner: false)
        } catch {
            statusMessage = error.localizedDescription
            messageDraft = body
        }
    }

    func saveNote() async {
        let body = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }

        noteDraft = ""
        do {
            try await community.postNote(sessionId: sessionId, body: body, verseRef: referenceForMutation)
            await loadSnapshot(showSpinner: false)
        } catch {
            statusMessage = error.localizedDescription
            noteDraft = body
        }
    }

    func react(_ reaction: String) async {
        do {
            try await community.addReaction(sessionId: sessionId, reaction: reaction)
            await loadSnapshot(showSpinner: false)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func moveToPhase(_ nextPhase: String) async {
        guard canLead else {
            statusMessage = "Only a study leader can guide the session."
            return
        }

        do {
            try await community.advancePhase(sessionId: sessionId, phase: nextPhase)
            await loadSnapshot(showSpinner: false)
            await trackPresence()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func endSession() async {
        guard canLead else {
            statusMessage = "Only a study leader can end the session."
            return
        }

        do {
            try await community.endSession(sessionId: sessionId)
            await loadSnapshot(showSpinner: false)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func configureQuiz(mode: String, durationSeconds: Int) async {
        guard canLead else {
            statusMessage = "Only a study leader can configure the quiz."
            return
        }

        do {
            try await community.configureQuiz(sessionId: sessionId, mode: mode, durationSeconds: durationSeconds)
            await loadSnapshot(showSpinner: false)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func startTimedQuiz(durationSeconds: Int) async {
        guard canLead else {
            statusMessage = "Only a study leader can start the timed quiz."
            return
        }

        do {
            try await community.startTimedQuiz(sessionId: sessionId, durationSeconds: durationSeconds)
            await loadSnapshot(showSpinner: false)
            await trackPresence()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func submitQuizAnswer(questionIndex: Int, selectedIndex: Int) async {
        do {
            try await community.submitQuizAnswer(
                sessionId: sessionId,
                questionIndex: questionIndex,
                selectedIndex: selectedIndex
            )
            await loadSnapshot(showSpinner: false)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func endTimedQuiz() async {
        guard canLead else {
            statusMessage = "Only a study leader can end the timed quiz."
            return
        }

        do {
            try await community.endTimedQuiz(sessionId: sessionId)
            await loadSnapshot(showSpinner: false)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private var referenceForMutation: String? {
        let value = reference
        return value == "Open study" ? nil : value
    }

    private func loadSnapshot(showSpinner: Bool) async {
        if showSpinner { isLoading = true }
        defer { if showSpinner { isLoading = false } }

        do {
            let loaded = try await community.sessionSnapshot(id: sessionId)
            snapshot = loaded
            statusMessage = isConnected ? "Live" : statusMessage
            await loadFocusVerseIfNeeded(snapshot: loaded)
            prepareGuideIfNeeded(snapshot: loaded)
            scheduleQuizAutoEndIfNeeded(snapshot: loaded)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func connect() async {
        guard SupabaseService.shared.isSignedIn else {
            statusMessage = "Sign in to join the live session."
            return
        }

        do {
            let session = try await SupabaseService.shared.currentSession()
            currentUserId = session.user.id.uuidString

            guard let realtimeURL = URL(string: "https://\(host)/realtime/v1") else {
                statusMessage = "Supabase Realtime is not configured."
                return
            }

            let client = RealtimeClientV2(
                url: realtimeURL,
                options: RealtimeClientOptions(
                    headers: [
                        "apiKey": anonKey,
                        "Authorization": "Bearer \(session.accessToken)"
                    ],
                    accessToken: {
                        try? await SupabaseService.shared.currentSession().accessToken
                    }
                )
            )

            let liveChannel = client.channel("study-session:\(sessionId)") { [currentUserId] config in
                config.isPrivate = true
                config.presence.key = currentUserId
                config.broadcast.acknowledgeBroadcasts = true
                config.broadcast.receiveOwnBroadcasts = true
            }

            realtime = client
            channel = liveChannel
            listen(on: liveChannel)

            try await liveChannel.subscribeWithError()
            isConnected = true
            statusMessage = "Live"
            await trackPresence()
        } catch {
            isConnected = false
            statusMessage = error.localizedDescription
        }
    }

    private func listen(on channel: RealtimeChannelV2) {
        broadcastTask?.cancel()
        presenceTask?.cancel()
        statusTask?.cancel()

        let broadcastStream = channel.broadcastStream(event: "session_changed")
        let presenceStream = channel.presenceChange()
        let statusStream = channel.statusChange

        broadcastTask = Task { [weak self] in
            for await _ in broadcastStream {
                self?.scheduleSnapshotRefresh()
            }
        }

        presenceTask = Task { [weak self] in
            for await action in presenceStream {
                let joins = (try? action.decodeJoins(as: StudyPresence.self)) ?? []
                let leaveKeys = Array(action.leaves.keys)
                self?.applyPresence(joins: joins, leaveKeys: leaveKeys)
            }
        }

        statusTask = Task { [weak self] in
            for await status in statusStream {
                self?.applyChannelStatus(status)
            }
        }
    }

    private func applyChannelStatus(_ status: RealtimeChannelStatus) {
        switch status {
        case .subscribed:
            isConnected = true
            statusMessage = "Live"
        case .subscribing:
            statusMessage = "Connecting..."
        case .unsubscribing, .unsubscribed:
            isConnected = false
            statusMessage = "Disconnected"
        }
    }

    private func scheduleSnapshotRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            await self?.loadSnapshot(showSpinner: false)
        }
    }

    private func applyPresence(joins: [StudyPresence], leaveKeys: [String]) {
        for key in leaveKeys {
            onlineByUserId[key] = nil
        }

        for presence in joins {
            onlineByUserId[presence.userId] = presence
        }

        onlineMembers = onlineByUserId.values.sorted { $0.name < $1.name }
    }

    private func trackPresence() async {
        guard let channel else { return }

        let profile = community.dashboard.profile
        let displayName = profile?.name.isEmpty == false
            ? profile?.name ?? "Friend"
            : SupabaseService.shared.userEmail

        let presence = StudyPresence(
            userId: currentUserId,
            name: displayName.isEmpty ? "Friend" : displayName,
            phase: phase,
            joinedAt: isoFormatter.string(from: Date())
        )

        onlineByUserId[currentUserId] = presence
        onlineMembers = onlineByUserId.values.sorted { $0.name < $1.name }
        try? await channel.track(presence)
    }

    private func loadFocusVerseIfNeeded(snapshot: StudySessionSnapshot) async {
        let reference = snapshot.session.reference
        let language = snapshot.session.language
        guard reference != "Open study" else {
            focusVerseText = nil
            focusVerseKey = ""
            return
        }

        let nextKey = "\(reference)|\(language)"
        guard focusVerseKey != nextKey else { return }

        focusVerseKey = nextKey
        focusVerseText = nil
        if let passage = await EthiopianBibleService.shared.passage(
            ref: reference,
            language: language
        ) {
            focusVerseText = passage
        } else {
            focusVerseText = await EthiopianBibleService.shared.verse(ref: reference, language: language)
        }
    }

    private func prepareGuideIfNeeded(snapshot: StudySessionSnapshot) {
        let session = snapshot.session
        guard session.status == "active",
              snapshot.room.canLead,
              session.reference != "Open study",
              session.guide == nil,
              !isGeneratingGuide,
              !attemptedGuideSessionIds.contains(session.id) else {
            if session.guide != nil {
                guideMessage = ""
            }
            return
        }

        attemptedGuideSessionIds.insert(session.id)
        guideGenerationTask?.cancel()
        guideGenerationTask = Task { [weak self] in
            await self?.generateGuide(for: session)
        }
    }

    private func generateGuide(for session: StudySessionInfo) async {
        isGeneratingGuide = true
        guideMessage = "Preparing study guide..."
        defer { isGeneratingGuide = false }

        do {
            let guide = try await studyGuide.generate(for: session)
            try await community.saveStudyGuide(sessionId: session.id, guide: guide)
            guideMessage = "Guide ready"
            await loadSnapshot(showSpinner: false)
        } catch {
            guideMessage = error.localizedDescription
            try? await community.markStudyGuideFailed(sessionId: session.id)
            await loadSnapshot(showSpinner: false)
        }
    }

    private func scheduleQuizAutoEndIfNeeded(snapshot: StudySessionSnapshot) {
        guard snapshot.room.canLead,
              snapshot.session.status == "active",
              snapshot.session.quizMode == "timed",
              snapshot.session.quizStatus == "running",
              let startedAt = parseDate(snapshot.session.quizStartedAt) else {
            quizAutoEndTask?.cancel()
            quizAutoEndTask = nil
            scheduledQuizEndKey = ""
            return
        }

        let key = "\(snapshot.session.id)|\(snapshot.session.quizStartedAt ?? "")|\(snapshot.session.quizDurationSeconds)"
        guard scheduledQuizEndKey != key else { return }

        quizAutoEndTask?.cancel()
        scheduledQuizEndKey = key

        let endDate = startedAt.addingTimeInterval(TimeInterval(snapshot.session.quizDurationSeconds))
        let delay = max(0, endDate.timeIntervalSinceNow)
        let nanoseconds = UInt64(delay * 1_000_000_000)

        quizAutoEndTask = Task { [weak self] in
            if nanoseconds > 0 {
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
            guard !Task.isCancelled else { return }
            await self?.endTimedQuiz()
        }
    }

    private func parseDate(_ value: String?) -> Date? {
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
}
