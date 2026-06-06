import Foundation
import Auth

struct CommunityDashboard: Decodable {
    let profile: CommunityProfile?
    let friends: [CommunityFriend]
    let incomingRequests: [CommunityRequest]
    let outgoingRequests: [CommunityRequest]
    let rooms: [StudyRoomSummary]

    static let empty = CommunityDashboard(
        profile: nil,
        friends: [],
        incomingRequests: [],
        outgoingRequests: [],
        rooms: []
    )

    enum CodingKeys: String, CodingKey {
        case profile, friends, rooms
        case incomingRequests = "incoming_requests"
        case outgoingRequests = "outgoing_requests"
    }
}

struct CommunityProfile: Decodable, Identifiable {
    let id: String
    let name: String
    let friendCode: String
    let avatarPath: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case friendCode = "friend_code"
        case avatarPath = "avatar_path"
    }
}

struct CommunityFriend: Decodable, Identifiable {
    let id: String
    let name: String
    let friendCode: String
    let avatarPath: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case friendCode = "friend_code"
        case avatarPath = "avatar_path"
        case createdAt = "created_at"
    }
}

struct CommunityRequest: Decodable, Identifiable {
    let id: String
    let userId: String
    let name: String
    let friendCode: String
    let avatarPath: String?
    let message: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, message
        case userId = "user_id"
        case friendCode = "friend_code"
        case avatarPath = "avatar_path"
        case createdAt = "created_at"
    }
}

struct StudyRoomSummary: Decodable, Identifiable {
    let id: String
    let name: String
    let description: String
    let defaultPackId: String
    let language: String
    let inviteCode: String
    let ownerId: String
    let role: String
    let memberStatus: String
    let memberCount: Int
    let activeSessionId: String?
    let updatedAt: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, description, language, role
        case defaultPackId = "default_pack_id"
        case inviteCode = "invite_code"
        case ownerId = "owner_id"
        case memberStatus = "member_status"
        case memberCount = "member_count"
        case activeSessionId = "active_session_id"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
    }

    var canLead: Bool {
        ["owner", "admin", "leader"].contains(role)
    }

    var canManageRoles: Bool {
        ["owner", "admin"].contains(role)
    }
}

struct StudySessionLaunch: Decodable {
    let id: String
    let roomId: String
    let phase: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, phase, status
        case roomId = "room_id"
    }
}

struct StudySessionSnapshot: Decodable {
    let session: StudySessionInfo
    let room: StudySessionRoom
    let messages: [StudySessionMessage]
    let notes: [StudySessionNote]
    let reactionCounts: [String: Int]
    let myReactions: [String]
    let quiz: StudySessionQuizState

    enum CodingKeys: String, CodingKey {
        case session, room, messages, notes, quiz
        case reactionCounts = "reaction_counts"
        case myReactions = "my_reactions"
    }
}

struct StudySessionInfo: Decodable, Identifiable {
    let id: String
    let roomId: String
    let hostId: String
    let title: String
    let book: String
    let bookName: String
    let chapter: Int
    let verseStart: Int?
    let verseEnd: Int?
    let language: String
    let phase: String
    let status: String
    let startedAt: String
    let endedAt: String?
    let guideStatus: String?
    let guideGeneratedAt: String?
    let guide: PreparedStudyGuide?
    let quizMode: String
    let quizStatus: String
    let quizStartedAt: String?
    let quizEndedAt: String?
    let quizDurationSeconds: Int

    enum CodingKeys: String, CodingKey {
        case id, title, book, chapter, language, phase, status
        case guide
        case roomId = "room_id"
        case hostId = "host_id"
        case bookName = "book_name"
        case verseStart = "verse_start"
        case verseEnd = "verse_end"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case guideStatus = "guide_status"
        case guideGeneratedAt = "guide_generated_at"
        case quizMode = "quiz_mode"
        case quizStatus = "quiz_status"
        case quizStartedAt = "quiz_started_at"
        case quizEndedAt = "quiz_ended_at"
        case quizDurationSeconds = "quiz_duration_seconds"
    }

    var reference: String {
        guard !bookName.isEmpty || !book.isEmpty else { return "Open study" }
        let displayBook = bookName.isEmpty ? book : bookName
        if let verseStart {
            if let verseEnd, verseEnd != verseStart {
                return "\(displayBook) \(chapter):\(verseStart)-\(verseEnd)"
            }
            return "\(displayBook) \(chapter):\(verseStart)"
        }
        return "\(displayBook) \(chapter)"
    }
}

struct StudySessionRoom: Decodable {
    let id: String
    let name: String
    let description: String
    let defaultPackId: String
    let language: String
    let inviteCode: String
    let myRole: String
    let canLead: Bool
    let canManageRoles: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, description, language
        case defaultPackId = "default_pack_id"
        case inviteCode = "invite_code"
        case myRole = "my_role"
        case canLead = "can_lead"
        case canManageRoles = "can_manage_roles"
    }
}

struct StudyRoomMembersSnapshot: Decodable {
    let roomId: String
    let myRole: String
    let canManageRoles: Bool
    let members: [StudyRoomMember]

    enum CodingKeys: String, CodingKey {
        case members
        case roomId = "room_id"
        case myRole = "my_role"
        case canManageRoles = "can_manage_roles"
    }
}

struct StudyRoomMember: Decodable, Identifiable, Equatable {
    let userId: String
    let name: String
    let friendCode: String
    let avatarPath: String?
    let role: String
    let status: String
    let joinedAt: String?
    let createdAt: String

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case name, role, status
        case userId = "user_id"
        case friendCode = "friend_code"
        case avatarPath = "avatar_path"
        case joinedAt = "joined_at"
        case createdAt = "created_at"
    }
}

struct StudySessionQuizState: Decodable, Equatable {
    let myAnswers: [StudySessionQuizAnswer]
    let results: [StudySessionQuizResult]
    let questionStats: [StudySessionQuizQuestionStat]
    let questionCount: Int

    enum CodingKeys: String, CodingKey {
        case results
        case myAnswers = "my_answers"
        case questionStats = "question_stats"
        case questionCount = "question_count"
    }
}

struct StudySessionQuizAnswer: Decodable, Identifiable, Equatable {
    let questionIndex: Int
    let selectedIndex: Int
    let isCorrect: Bool?
    let answeredAt: String

    var id: Int { questionIndex }

    enum CodingKeys: String, CodingKey {
        case questionIndex = "question_index"
        case selectedIndex = "selected_index"
        case isCorrect = "is_correct"
        case answeredAt = "answered_at"
    }
}

struct StudySessionQuizResult: Decodable, Identifiable, Equatable {
    let userId: String
    let userName: String
    let avatarPath: String?
    let answered: Int
    let correct: Int
    let total: Int
    let isComplete: Bool

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case answered, correct, total
        case userId = "user_id"
        case userName = "user_name"
        case avatarPath = "avatar_path"
        case isComplete = "is_complete"
    }
}

struct StudySessionQuizQuestionStat: Decodable, Identifiable, Equatable {
    let questionIndex: Int
    let answerCounts: [Int]
    let correctIndex: Int?

    var id: Int { questionIndex }

    enum CodingKeys: String, CodingKey {
        case questionIndex = "question_index"
        case answerCounts = "answer_counts"
        case correctIndex = "correct_index"
    }
}

struct StudySessionMessage: Decodable, Identifiable, Equatable {
    let id: String
    let sessionId: String
    let roomId: String
    let userId: String
    let userName: String
    let avatarPath: String?
    let kind: String
    let body: String
    let verseRef: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, kind, body
        case sessionId = "session_id"
        case roomId = "room_id"
        case userId = "user_id"
        case userName = "user_name"
        case avatarPath = "avatar_path"
        case verseRef = "verse_ref"
        case createdAt = "created_at"
    }
}

struct StudySessionNote: Decodable, Identifiable, Equatable {
    let id: String
    let sessionId: String
    let roomId: String
    let userId: String
    let userName: String
    let avatarPath: String?
    let verseRef: String?
    let body: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, body
        case sessionId = "session_id"
        case roomId = "room_id"
        case userId = "user_id"
        case userName = "user_name"
        case avatarPath = "avatar_path"
        case verseRef = "verse_ref"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

@MainActor
@Observable
final class CommunityService {
    static let shared = CommunityService()

    private let host: String
    private let anonKey: String
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private(set) var dashboard: CommunityDashboard = .empty
    private(set) var isLoading = false
    private(set) var statusMessage = ""

    private init() {
        host = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_HOST") as? String ?? ""
        anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
    }

    func refresh() async {
        guard SupabaseService.shared.isSignedIn else {
            dashboard = .empty
            statusMessage = "Sign in to study with friends."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            dashboard = try await rpc("community_dashboard", body: EmptyBody())
            statusMessage = ""
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func sendFriendRequest(code: String, message: String) async {
        await mutate("Sending request...") {
            let _: MutationResponse = try await rpc(
                "send_friend_request_by_code",
                body: FriendRequestBody(targetCode: code, requestMessage: message)
            )
        }
    }

    func respondToFriendRequest(id: String, accept: Bool) async {
        await mutate(accept ? "Accepting request..." : "Declining request...") {
            let _: MutationResponse = try await rpc(
                "respond_friend_request",
                body: FriendResponseBody(requestId: id, accept: accept)
            )
        }
    }

    func createRoom(name: String, description: String, packId: String, language: String) async {
        await mutate("Creating room...") {
            let _: MutationResponse = try await rpc(
                "create_study_room",
                body: CreateRoomBody(
                    roomName: name,
                    roomDescription: description,
                    defaultPack: packId,
                    roomLanguage: language
                )
            )
        }
    }

    func joinRoom(code: String) async {
        await mutate("Joining room...") {
            let _: MutationResponse = try await rpc(
                "join_study_room_by_code",
                body: JoinRoomBody(targetCode: code)
            )
        }
    }

    func roomMembers(roomId: String) async throws -> StudyRoomMembersSnapshot {
        try await rpc("study_room_members_snapshot", body: RoomIdBody(targetRoomId: roomId))
    }

    func setRoomMemberRole(roomId: String, userId: String, role: String) async {
        await mutate("Updating role...") {
            let _: MutationResponse = try await rpc(
                "set_study_room_member_role",
                body: SetRoomMemberRoleBody(targetRoomId: roomId, targetUserId: userId, nextRole: role)
            )
        }
    }

    func startSession(room: StudyRoomSummary) async -> String? {
        let focus = VerseMasteryService.shared.practiceQuestionsForToday(
            packId: room.defaultPackId,
            count: 1
        ).first
        let parsedRef = focus.flatMap { Self.parseVerseReference($0.verseRef) }

        return await mutate("Starting session...") {
            let launch: StudySessionLaunch = try await rpc(
                "create_study_session",
                body: CreateSessionBody(
                    targetRoomId: room.id,
                    sessionTitle: "\(VersePack.find(room.defaultPackId).name) study",
                    targetBook: parsedRef?.book ?? focus?.book ?? "",
                    targetBookName: parsedRef?.book ?? focus?.book ?? "",
                    targetChapter: parsedRef?.chapter ?? 1,
                    targetVerseStart: parsedRef?.verse,
                    targetVerseEnd: parsedRef?.verse,
                    targetLanguage: room.language
                )
            )
            return launch.id
        }
    }

    func sessionSnapshot(id: String) async throws -> StudySessionSnapshot {
        try await rpc("study_session_snapshot", body: SessionIdBody(targetSessionId: id))
    }

    func postMessage(sessionId: String, body: String, kind: String = "chat", verseRef: String? = nil) async throws {
        let _: MutationResponse = try await rpc(
            "post_study_session_message",
            body: PostMessageBody(
                targetSessionId: sessionId,
                messageBody: body,
                messageKind: kind,
                messageVerseRef: verseRef
            )
        )
    }

    func postNote(sessionId: String, body: String, verseRef: String? = nil) async throws {
        let _: MutationResponse = try await rpc(
            "post_study_session_note",
            body: PostNoteBody(
                targetSessionId: sessionId,
                noteBody: body,
                noteVerseRef: verseRef
            )
        )
    }

    func addReaction(sessionId: String, reaction: String, targetType: String = "session", targetId: String? = nil) async throws {
        let _: MutationResponse = try await rpc(
            "add_study_session_reaction",
            body: ReactionBody(
                targetSessionId: sessionId,
                reactionName: reaction,
                targetKind: targetType,
                targetUuid: targetId
            )
        )
    }

    func saveStudyGuide(sessionId: String, guide: PreparedStudyGuide, status: String = "ready") async throws {
        let _: MutationResponse = try await rpc(
            "save_study_session_guide",
            body: SaveStudyGuideBody(
                targetSessionId: sessionId,
                guidePayload: guide,
                nextStatus: status
            )
        )
    }

    func markStudyGuideFailed(sessionId: String) async throws {
        let _: MutationResponse = try await rpc(
            "save_study_session_guide",
            body: FailedStudyGuideBody(targetSessionId: sessionId)
        )
    }

    func advancePhase(sessionId: String, phase: String) async throws {
        let _: MutationResponse = try await rpc(
            "advance_study_session_phase",
            body: PhaseBody(targetSessionId: sessionId, nextPhase: phase)
        )
    }

    func configureQuiz(sessionId: String, mode: String, durationSeconds: Int) async throws {
        let _: MutationResponse = try await rpc(
            "configure_study_session_quiz",
            body: ConfigureQuizBody(targetSessionId: sessionId, nextMode: mode, durationSeconds: durationSeconds)
        )
    }

    func startTimedQuiz(sessionId: String, durationSeconds: Int) async throws {
        let _: MutationResponse = try await rpc(
            "start_study_session_quiz",
            body: StartQuizBody(targetSessionId: sessionId, durationSeconds: durationSeconds)
        )
    }

    func submitQuizAnswer(sessionId: String, questionIndex: Int, selectedIndex: Int) async throws {
        let _: MutationResponse = try await rpc(
            "submit_study_session_quiz_answer",
            body: SubmitQuizAnswerBody(
                targetSessionId: sessionId,
                questionNumber: questionIndex,
                selectedNumber: selectedIndex
            )
        )
    }

    func endTimedQuiz(sessionId: String) async throws {
        let _: MutationResponse = try await rpc("end_study_session_quiz", body: SessionIdBody(targetSessionId: sessionId))
    }

    func endSession(sessionId: String) async throws {
        let _: MutationResponse = try await rpc("end_study_session", body: SessionIdBody(targetSessionId: sessionId))
    }

    private func mutate<T>(_ pendingMessage: String, operation: () async throws -> T) async -> T? {
        guard SupabaseService.shared.isSignedIn else {
            statusMessage = "Sign in to continue."
            return nil
        }

        isLoading = true
        statusMessage = pendingMessage
        defer { isLoading = false }

        do {
            let result = try await operation()
            await refresh()
            return result
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
    }

    private func rpc<Response: Decodable, Body: Encodable>(_ function: String, body: Body) async throws -> Response {
        let session = try await SupabaseService.shared.currentSession()
        guard let url = URL(string: "https://\(host)/rest/v1/rpc/\(function)") else {
            throw CommunityError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            if let error = try? decoder.decode(SupabaseRPCError.self, from: data) {
                throw CommunityError.remote(error.message)
            }
            throw CommunityError.remote("Supabase request failed (\(statusCode)).")
        }

        return try decoder.decode(Response.self, from: data)
    }

    private static func parseVerseReference(_ ref: String) -> (book: String, chapter: Int, verse: Int)? {
        let pattern = #"^(.+?)\s+(\d+):(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: ref, range: NSRange(ref.startIndex..., in: ref)),
              let bookRange = Range(match.range(at: 1), in: ref),
              let chapterRange = Range(match.range(at: 2), in: ref),
              let verseRange = Range(match.range(at: 3), in: ref),
              let chapter = Int(ref[chapterRange]),
              let verse = Int(ref[verseRange]) else {
            return nil
        }

        return (String(ref[bookRange]), chapter, verse)
    }
}

private struct EmptyBody: Encodable {}

private struct FriendRequestBody: Encodable {
    let targetCode: String
    let requestMessage: String

    enum CodingKeys: String, CodingKey {
        case targetCode = "target_code"
        case requestMessage = "request_message"
    }
}

private struct FriendResponseBody: Encodable {
    let requestId: String
    let accept: Bool

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case accept
    }
}

private struct CreateRoomBody: Encodable {
    let roomName: String
    let roomDescription: String
    let defaultPack: String
    let roomLanguage: String

    enum CodingKeys: String, CodingKey {
        case roomName = "room_name"
        case roomDescription = "room_description"
        case defaultPack = "default_pack"
        case roomLanguage = "room_language"
    }
}

private struct JoinRoomBody: Encodable {
    let targetCode: String

    enum CodingKeys: String, CodingKey {
        case targetCode = "target_code"
    }
}

private struct RoomIdBody: Encodable {
    let targetRoomId: String

    enum CodingKeys: String, CodingKey {
        case targetRoomId = "target_room_id"
    }
}

private struct SetRoomMemberRoleBody: Encodable {
    let targetRoomId: String
    let targetUserId: String
    let nextRole: String

    enum CodingKeys: String, CodingKey {
        case targetRoomId = "target_room_id"
        case targetUserId = "target_user_id"
        case nextRole = "next_role"
    }
}

private struct CreateSessionBody: Encodable {
    let targetRoomId: String
    let sessionTitle: String
    let targetBook: String
    let targetBookName: String
    let targetChapter: Int
    let targetVerseStart: Int?
    let targetVerseEnd: Int?
    let targetLanguage: String

    enum CodingKeys: String, CodingKey {
        case targetRoomId = "target_room_id"
        case sessionTitle = "session_title"
        case targetBook = "target_book"
        case targetBookName = "target_book_name"
        case targetChapter = "target_chapter"
        case targetVerseStart = "target_verse_start"
        case targetVerseEnd = "target_verse_end"
        case targetLanguage = "target_language"
    }
}

private struct SessionIdBody: Encodable {
    let targetSessionId: String

    enum CodingKeys: String, CodingKey {
        case targetSessionId = "target_session_id"
    }
}

private struct PostMessageBody: Encodable {
    let targetSessionId: String
    let messageBody: String
    let messageKind: String
    let messageVerseRef: String?

    enum CodingKeys: String, CodingKey {
        case targetSessionId = "target_session_id"
        case messageBody = "message_body"
        case messageKind = "message_kind"
        case messageVerseRef = "message_verse_ref"
    }
}

private struct PostNoteBody: Encodable {
    let targetSessionId: String
    let noteBody: String
    let noteVerseRef: String?

    enum CodingKeys: String, CodingKey {
        case targetSessionId = "target_session_id"
        case noteBody = "note_body"
        case noteVerseRef = "note_verse_ref"
    }
}

private struct ReactionBody: Encodable {
    let targetSessionId: String
    let reactionName: String
    let targetKind: String
    let targetUuid: String?

    enum CodingKeys: String, CodingKey {
        case targetSessionId = "target_session_id"
        case reactionName = "reaction_name"
        case targetKind = "target_kind"
        case targetUuid = "target_uuid"
    }
}

private struct SaveStudyGuideBody: Encodable {
    let targetSessionId: String
    let guidePayload: PreparedStudyGuide
    let nextStatus: String

    enum CodingKeys: String, CodingKey {
        case targetSessionId = "target_session_id"
        case guidePayload = "guide_payload"
        case nextStatus = "next_status"
    }
}

private struct FailedStudyGuideBody: Encodable {
    let targetSessionId: String
    let guidePayload: [String: String] = [:]
    let nextStatus = "failed"

    enum CodingKeys: String, CodingKey {
        case targetSessionId = "target_session_id"
        case guidePayload = "guide_payload"
        case nextStatus = "next_status"
    }
}

private struct PhaseBody: Encodable {
    let targetSessionId: String
    let nextPhase: String

    enum CodingKeys: String, CodingKey {
        case targetSessionId = "target_session_id"
        case nextPhase = "next_phase"
    }
}

private struct ConfigureQuizBody: Encodable {
    let targetSessionId: String
    let nextMode: String
    let durationSeconds: Int

    enum CodingKeys: String, CodingKey {
        case targetSessionId = "target_session_id"
        case nextMode = "next_mode"
        case durationSeconds = "duration_seconds"
    }
}

private struct StartQuizBody: Encodable {
    let targetSessionId: String
    let durationSeconds: Int

    enum CodingKeys: String, CodingKey {
        case targetSessionId = "target_session_id"
        case durationSeconds = "duration_seconds"
    }
}

private struct SubmitQuizAnswerBody: Encodable {
    let targetSessionId: String
    let questionNumber: Int
    let selectedNumber: Int

    enum CodingKeys: String, CodingKey {
        case targetSessionId = "target_session_id"
        case questionNumber = "question_number"
        case selectedNumber = "selected_number"
    }
}

private struct MutationResponse: Decodable {
    let status: String?
    let id: String?
}

private struct SupabaseRPCError: Decodable {
    let message: String
}

private enum CommunityError: LocalizedError {
    case invalidConfiguration
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Supabase is not configured."
        case .remote(let message):
            return message
        }
    }
}
