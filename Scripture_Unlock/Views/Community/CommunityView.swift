import SwiftUI
import UIKit

struct CommunityView: View {
    @Environment(SupabaseService.self) private var supabase
    @Environment(NavigationRouter.self) private var router
    @State private var community = CommunityService.shared
    @State private var showAddFriend = false
    @State private var showCreateRoom = false
    @State private var showJoinRoom = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if supabase.isSignedIn {
                        signedInContent
                    } else {
                        signedOutContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
            .background(DesignSystem.warmCream.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task(id: supabase.isSignedIn) {
                await community.refresh()
            }
            .sheet(isPresented: $showAddFriend) {
                AddFriendSheet { code, message in
                    Task {
                        await community.sendFriendRequest(code: code, message: message)
                        ToastService.shared.friendRequestSent()
                    }
                }
            }
            .sheet(isPresented: $showCreateRoom) {
                CreateRoomSheet { name, description, packId, language in
                    Task {
                        await community.createRoom(name: name, description: description, packId: packId, language: language)
                        ToastService.shared.roomCreated()
                    }
                }
            }
            .sheet(isPresented: $showJoinRoom) {
                JoinRoomSheet { code in
                    Task {
                        await community.joinRoom(code: code)
                        ToastService.shared.roomJoined()
                    }
                }
            }
        }
    }

    private var signedInContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let profile = community.dashboard.profile {
                FriendCodeCard(profile: profile)
            }

            HStack(spacing: 10) {
                actionButton("Add", icon: "person.badge.plus.fill") { showAddFriend = true }
                actionButton("Create", icon: "plus.bubble.fill") { showCreateRoom = true }
                actionButton("Join", icon: "link.circle.fill") { showJoinRoom = true }
                AppIconButton(
                    systemName: "arrow.clockwise",
                    style: .secondary,
                    size: 40,
                    disabled: community.isLoading
                ) {
                    Task { await community.refresh() }
                }
            }

            if community.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }

            if !community.statusMessage.isEmpty {
                Text(community.statusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignSystem.slate600)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            requestsSection
            friendsSection
            roomsSection
            leaderboardSection
        }
    }

    private var signedOutContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                Circle()
                    .fill(DesignSystem.royalBlue.opacity(0.12))
                    .frame(width: 58, height: 58)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(DesignSystem.royalBlue)
            }

            Text("Study with friends")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(DesignSystem.ink)

            Text("Sign in to create private Bible study rooms, share your friend code, and build group streaks.")
                .font(.system(size: 14))
                .foregroundStyle(DesignSystem.slate600)
                .fixedSize(horizontal: false, vertical: true)

            AppActionButton(
                title: "Open Settings",
                icon: "person.crop.circle.badge.checkmark"
            ) {
                router.selectedTab = .settings
            }
        }
        .padding(18)
        .cardStyle()
    }

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Requests")

            if community.dashboard.incomingRequests.isEmpty && community.dashboard.outgoingRequests.isEmpty {
                emptyRow("No pending friend requests.", icon: "tray.fill")
            } else {
                ForEach(community.dashboard.incomingRequests) { request in
                    RequestRow(request: request) { accept in
                        Task {
                                await community.respondToFriendRequest(id: request.id, accept: accept)
                                if accept { ToastService.shared.friendAccepted() }
                                else      { ToastService.shared.friendDeclined() }
                            }
                    }
                }

                ForEach(community.dashboard.outgoingRequests) { request in
                    HStack(spacing: 12) {
                        AvatarCircle(name: request.name, avatarPath: request.avatarPath, size: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(request.name.isEmpty ? "Pending friend" : request.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DesignSystem.ink)
                            Text("Request sent")
                                .font(.system(size: 12))
                                .foregroundStyle(DesignSystem.slate600)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .cardStyle()
                }
            }
        }
    }

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Friends")

            if community.dashboard.friends.isEmpty {
                emptyRow("Add a friend to start shared study.", icon: "person.2")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(community.dashboard.friends) { friend in
                            VStack(spacing: 8) {
                                AvatarCircle(name: friend.name, avatarPath: friend.avatarPath, size: 48)
                                Text(friend.name.isEmpty ? "Friend" : friend.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(DesignSystem.ink)
                                    .lineLimit(1)
                            }
                            .frame(width: 84)
                            .padding(.vertical, 12)
                            .background(DesignSystem.surface)
                            .cornerRadius(14)
                            .shadow(color: DesignSystem.shadow1, radius: 6, x: 0, y: 2)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var roomsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Study Rooms")

            if community.dashboard.rooms.isEmpty {
                emptyRow("Create a room for morning study, family reading, or a verse pack group.", icon: "bubble.left.and.bubble.right.fill")
            } else {
                ForEach(community.dashboard.rooms) { room in
                    NavigationLink {
                        StudyRoomDetailView(room: room)
                    } label: {
                        StudyRoomRow(room: room)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Leaderboard")
                Spacer()
                NavigationLink {
                    LeaderboardView()
                } label: {
                    Text("See all")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DesignSystem.royalBlue)
                }
            }

            NavigationLink {
                LeaderboardView()
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(DesignSystem.pastoralGold.opacity(0.14))
                            .frame(width: 42, height: 42)
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(DesignSystem.pastoralGold)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("View friend rankings")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(DesignSystem.ink)
                        Text("Compare Scripture accuracy with friends")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignSystem.slate600)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DesignSystem.slate400)
                }
                .padding(14)
                .cardStyle()
            }
            .buttonStyle(.plain)
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        AppActionButton(
            title: title,
            icon: icon,
            style: .secondary,
            size: .compact,
            action: action
        )
    }

    private func emptyRow(_ text: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DesignSystem.slate400)
                .frame(width: 34, height: 34)
                .background(DesignSystem.slate400.opacity(0.12))
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(DesignSystem.slate600)
            Spacer()
        }
        .padding(14)
        .cardStyle()
    }
}

private struct FriendCodeCard: View {
    let profile: CommunityProfile
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AvatarCircle(name: profile.name, avatarPath: profile.avatarPath, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name.isEmpty ? "Your community profile" : profile.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(DesignSystem.ink)
                    Text("Share your friend code")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.slate600)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Text(profile.friendCode)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignSystem.royalBlue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(DesignSystem.royalBlue.opacity(0.08))
                    .cornerRadius(10)

                AppIconButton(
                    systemName: copied ? "checkmark" : "doc.on.doc.fill",
                    style: copied ? .success : .primary,
                    size: 42
                ) {
                    UIPasteboard.general.string = profile.friendCode
                    withAnimation(.easeInOut(duration: 0.15)) { copied = true }
                }
            }
        }
        .padding(16)
        .cardStyle()
    }
}

private struct RequestRow: View {
    let request: CommunityRequest
    let onRespond: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AvatarCircle(name: request.name, avatarPath: request.avatarPath, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.name.isEmpty ? "Friend request" : request.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DesignSystem.ink)
                    Text(request.friendCode)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(DesignSystem.slate600)
                }
                Spacer()
            }

            if !request.message.isEmpty {
                Text(request.message)
                    .font(.system(size: 13))
                    .foregroundStyle(DesignSystem.slate700)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                AppActionButton(title: "Accept", icon: "checkmark", style: .success, size: .compact) {
                    onRespond(true)
                }
                AppActionButton(title: "Decline", icon: "xmark", style: .neutral, size: .compact) {
                    onRespond(false)
                }
            }
        }
        .padding(14)
        .cardStyle()
    }
}

private struct StudyRoomRow: View {
    let room: StudyRoomSummary

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(DesignSystem.deepBlueGradient)
                    .frame(width: 52, height: 52)
                Image(systemName: room.activeSessionId == nil ? "book.pages.fill" : "dot.radiowaves.left.and.right")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(room.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(DesignSystem.ink)
                        .lineLimit(1)
                    if room.memberStatus == "invited" {
                        Text("Invited")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(DesignSystem.pastoralGold)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(DesignSystem.pastoralGold.opacity(0.12))
                            .cornerRadius(7)
                    }
                }
                Text(room.description.isEmpty ? VersePack.find(room.defaultPackId).name : room.description)
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.slate600)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Label("\(room.memberCount)", systemImage: "person.2.fill")
                    Label(room.inviteCode, systemImage: "link")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignSystem.slate400)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DesignSystem.slate400)
        }
        .padding(14)
        .cardStyle()
    }
}

struct StudyRoomDetailView: View {
    let room: StudyRoomSummary
    @State private var community = CommunityService.shared
    @State private var copied = false
    @State private var launchedSession: StudySessionRoute?
    @State private var membersSnapshot: StudyRoomMembersSnapshot?
    @State private var memberStatusMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(room.name)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(DesignSystem.ink)
                    Text(room.description.isEmpty ? "A private Scripture Unlock study room." : room.description)
                        .font(.system(size: 14))
                        .foregroundStyle(DesignSystem.slate600)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Invite")
                    HStack(spacing: 10) {
                        Text(room.inviteCode)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(DesignSystem.royalBlue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        AppIconButton(
                            systemName: copied ? "checkmark" : "doc.on.doc.fill",
                            style: copied ? .success : .primary,
                            size: 38
                        ) {
                            UIPasteboard.general.string = room.inviteCode
                            copied = true
                        }
                    }
                    .padding(14)
                    .cardStyle()
                }

                membersSection

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Session")
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("\(room.memberCount) members", systemImage: "person.2.fill")
                            Spacer()
                            Label(VersePack.find(room.defaultPackId).name, systemImage: "book.fill")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.slate600)

                        Text(room.activeSessionId == nil ? "No live session is active." : "A live session is ready for this room.")
                            .font(.system(size: 14))
                            .foregroundStyle(DesignSystem.ink)

                        if let activeSessionId = room.activeSessionId {
                            NavigationLink {
                                StudySessionView(sessionId: activeSessionId)
                            } label: {
                                AppActionLabel(
                                    title: "Join Live Session",
                                    icon: "dot.radiowaves.left.and.right",
                                    style: .success
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        AppActionButton(
                            title: room.activeSessionId == nil ? "Start Guided Session" : "Start New Session",
                            icon: "play.circle.fill",
                            disabled: !room.canLead
                        ) {
                            Task {
                                if let id = await community.startSession(room: room) {
                                    launchedSession = StudySessionRoute(id: id)
                                }
                            }
                        }

                        if !room.canLead {
                            Label("Only a room owner, admin, or study leader can start guided sessions.", systemImage: "lock.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(DesignSystem.slate600)
                        }
                    }
                    .padding(14)
                    .cardStyle()
                }

                if !community.statusMessage.isEmpty {
                    Text(community.statusMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignSystem.slate600)
                }
            }
            .padding(20)
        }
        .background(DesignSystem.warmCream.ignoresSafeArea())
        .navigationTitle("Study Room")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $launchedSession) { route in
            StudySessionView(sessionId: route.id)
        }
        .task {
            await loadMembers()
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Members")
                Spacer()
                AppToolbarIconButton(systemName: "arrow.clockwise") {
                    Task { await loadMembers() }
                }
            }

            if let snapshot = membersSnapshot {
                VStack(spacing: 10) {
                    ForEach(snapshot.members) { member in
                        StudyRoomMemberRow(
                            member: member,
                            canManageRoles: snapshot.canManageRoles,
                            canAssignAdmin: snapshot.myRole == "owner",
                            onRoleChange: { role in
                                Task {
                                    await community.setRoomMemberRole(roomId: room.id, userId: member.userId, role: role)
                                    await loadMembers()
                                }
                            }
                        )
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(DesignSystem.royalBlue)
                    Text("Loading members")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DesignSystem.slate600)
                    Spacer()
                }
                .padding(14)
                .cardStyle()
            }

            if !memberStatusMessage.isEmpty {
                Text(memberStatusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignSystem.slate600)
            }
        }
    }

    private func loadMembers() async {
        do {
            membersSnapshot = try await community.roomMembers(roomId: room.id)
            memberStatusMessage = ""
        } catch {
            memberStatusMessage = error.localizedDescription
        }
    }
}

private struct StudySessionRoute: Identifiable, Hashable {
    let id: String
}

private struct StudyRoomMemberRow: View {
    let member: StudyRoomMember
    let canManageRoles: Bool
    let canAssignAdmin: Bool
    let onRoleChange: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            AvatarCircle(name: member.name, avatarPath: member.avatarPath, size: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(member.name.isEmpty ? "Friend" : member.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DesignSystem.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    roleBadge(member.role)
                    if member.status != "active" {
                        Text(member.status.capitalized)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(DesignSystem.slate600)
                    }
                }
            }

            Spacer()

            if canManageRoles && member.role != "owner" {
                Menu {
                    if canAssignAdmin {
                        Button("Admin") { onRoleChange("admin") }
                    }
                    Button("Study Leader") { onRoleChange("leader") }
                    Button("Member") { onRoleChange("member") }
                } label: {
                    Image(systemName: "person.crop.circle.badge.gearshape.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DesignSystem.royalBlue)
                        .frame(width: 38, height: 38)
                        .background(DesignSystem.royalBlue.opacity(0.08))
                        .cornerRadius(10)
                }
            }
        }
        .padding(14)
        .cardStyle()
    }

    private func roleBadge(_ role: String) -> some View {
        Text(roleTitle(role))
            .font(.system(size: 10, weight: .black))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(roleColor(role))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(roleColor(role).opacity(0.11))
            .cornerRadius(8)
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

struct AvatarCircle: View {
    let name: String
    let avatarPath: String
    let size: CGFloat

    init(name: String, avatarPath: String? = nil, size: CGFloat) {
        self.name = name
        self.avatarPath = avatarPath ?? ""
        self.size = size
    }

    var body: some View {
        ProfileAvatarView(
            name: name,
            avatarPath: avatarPath,
            size: size,
            fallback: .initials,
            showsGlow: false
        )
    }
}

private struct AddFriendSheet: View {
    let onSend: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var message = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Friend code") {
                    TextField("SU-ABC123", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Optional note", text: $message, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Add Friend")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    AppToolbarTextButton(title: "Cancel", style: .neutral) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    AppToolbarTextButton(
                        title: "Send",
                        disabled: code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        onSend(code.trimmingCharacters(in: .whitespacesAndNewlines), message)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct CreateRoomSheet: View {
    let onCreate: (String, String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var packId = VersePack.psalms.id
    @State private var language = "en"

    var body: some View {
        NavigationStack {
            Form {
                Section("Room") {
                    TextField("Morning Study", text: $name)
                    TextField("Optional description", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("Defaults") {
                    Picker("Verse pack", selection: $packId) {
                        ForEach(VersePack.all) { pack in
                            Text(pack.name).tag(pack.id)
                        }
                    }
                    Picker("Language", selection: $language) {
                        Text("English").tag("en")
                        Text("Amharic").tag("am")
                        Text("Afaan Oromoo").tag("or")
                        Text("Tigrigna").tag("ti")
                    }
                }
            }
            .navigationTitle("Create Room")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    AppToolbarTextButton(title: "Cancel", style: .neutral) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    AppToolbarTextButton(
                        title: "Create",
                        disabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        onCreate(name.trimmingCharacters(in: .whitespacesAndNewlines), description, packId, language)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct JoinRoomSheet: View {
    let onJoin: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Invite code") {
                    TextField("ROOM-ABC123", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Join Room")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    AppToolbarTextButton(title: "Cancel", style: .neutral) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    AppToolbarTextButton(
                        title: "Join",
                        disabled: code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        onJoin(code.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                }
            }
        }
    }
}
