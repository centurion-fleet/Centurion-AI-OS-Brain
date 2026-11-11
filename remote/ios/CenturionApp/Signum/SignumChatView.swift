import SwiftUI
import UIKit

/// Signum — the whole product in one screen.
///
/// The rule this screen is built to: **one conversation, one composer, one name.**
/// No tabs, no dashboard, no modes. Everything an owner needs from the phone is
/// here — the thread, the fact that their Centurion is working, an honest
/// statement of what it is doing while it works, and the way back to pairing when
/// the link is down.
///
/// It reuses the existing transport end to end (`MessageService.sendMessage` →
/// `ConnectionManager`), so sessions, encryption, persistence and the tool
/// approval handshake all behave exactly as they already do. This is a new face
/// on a proven body, not a parallel chat stack — that distinction is what makes
/// it safe to ship in a build nobody can compile here.
struct SignumChatView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var messageService: MessageService
    @EnvironmentObject private var missionStore: MissionStore
    @EnvironmentObject private var adrianService: AdrianService

    @StateObject private var identity = SignumIdentity()

    @State private var draft = ""
    @State private var isSending = false
    @State private var sendError: String?
    @State private var lastFailed: String?
    @State private var conversationId: UUID?
    @State private var showConversations = false
    @State private var showConnect = false
    /// Set when the owner stops a turn themselves — suppress the error card that
    /// the aborted request would otherwise raise.
    @State private var didCancelTurn = false
    /// Command output in the thread. Not part of the conversation: nobody said it,
    /// it must never be sent to the model, and it must not reappear as history.
    @State private var systemEntries: [SignumSystemEntry] = []
    /// A command round-trip is in flight. Blocks a second send, not the composer.
    @State private var isRunningCommand = false
    /// Guards `isSending` against a cancelled turn's task finishing after a new
    /// one has already started.
    @State private var turnToken = 0
    @FocusState private var composerFocused: Bool

    private var conversation: Conversation? {
        guard let conversationId else { return nil }
        return messageService.conversations.first { $0.id == conversationId }
    }

    private var messages: [Message] {
        guard let conversationId else { return [] }
        return messageService.messages(for: conversationId)
    }

    private var isLinked: Bool { connectionManager.isChatComposerReady }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(SignumTheme.hair)
            thread
            composerArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SignumTheme.cream.ignoresSafeArea())
        .sheet(isPresented: $showConversations) {
            SignumConversationList(
                selectedId: conversationId,
                onSelect: { picked in
                    showConversations = false
                    Haptics.lightTap()
                    Task { @MainActor in
                        let opened = await messageService.openHostTopic(picked)
                        conversationId = opened.id
                    }
                },
                onNew: {
                    startNewConversation()
                    showConversations = false
                },
                onDelete: { doomed in
                    Task { @MainActor in
                        await messageService.deleteHostTopic(doomed)
                        if conversationId == doomed.id {
                            conversationId = nil
                            resolveConversation()
                        }
                    }
                }
            )
            .environmentObject(messageService)
            .environmentObject(connectionManager)
            .onAppear {
                guard connectionManager.isChatComposerReady else { return }
                Task { @MainActor in
                    _ = await messageService.syncHostTopicsFromBrain()
                }
            }
        }
        .fullScreenCover(isPresented: $showConnect) {
            ZStack(alignment: .topTrailing) {
                ConnectionView()
                    .environmentObject(connectionManager)
                    .environmentObject(adrianService)
                    .environmentObject(missionStore)

                Button {
                    showConnect = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SignumTheme.ink.opacity(0.7))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(SignumTheme.surface))
                        .overlay(Circle().stroke(SignumTheme.hair, lineWidth: 1))
                }
                .padding(.top, 52)
                .padding(.trailing, 16)
                .accessibilityLabel("Close")
            }
            .onChange(of: connectionManager.isCryptoChatReady) { wasReady, isReady in
                if !wasReady && isReady {
                    showConnect = false
                }
            }
        }
        .task {
            resolveConversation()
            // Away-first: join the relay now, in parallel with whatever the LAN does.
            // Waiting for discovery to fail is how the old build spent twenty seconds
            // looking for a machine on another network.
            connectionManager.startAwayFirst()
            await identity.refresh(using: connectionManager)
        }
        .onChange(of: connectionManager.connectionState) { _, _ in
            Task { await identity.refresh(using: connectionManager) }
        }
    }

    // MARK: - Header — the name in the hero spot

    private var header: some View {
        HStack(spacing: 12) {
            // The status line says "tap to reconnect", so it has to be tappable:
            // the header is the only permanent affordance when the link is down.
            if isLinked {
                identityBlock
            } else {
                Button {
                    Haptics.lightTap()
                    showConnect = true
                } label: {
                    identityBlock
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens pairing")
            }

            Spacer(minLength: 8)

            Button {
                Haptics.lightTap()
                showConversations = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(SignumTheme.ink.opacity(0.55))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Conversations")
        }
        .padding(.horizontal, SignumTheme.Metrics.screenPadding)
        .padding(.bottom, 10)
    }

    private var identityBlock: some View {
        HStack(spacing: 12) {
            SignumMark(size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(identity.name)
                    .font(SignumTheme.serif(17, .semibold))
                    .foregroundStyle(SignumTheme.ink)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Circle()
                        .fill(isLinked ? SignumTheme.gold : SignumTheme.muted.opacity(0.5))
                        .frame(width: 6, height: 6)
                    Text(statusLine)
                        .font(SignumTheme.mono(9.5))
                        .tracking(1.1)
                        .foregroundStyle(SignumTheme.muted)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var statusLine: String {
        // Away-first: the old line said "THIS MACHINE" whenever the socket was up, which
        // became a lie the moment the relay was the socket. An owner on a train deserves
        // to know which of the two paths is carrying their conversation.
        if connectionManager.isRelayAwayConnected {
            return "CONNECTED · AWAY"
        }
        switch connectionManager.connectionState {
        case .connected:
            return "CONNECTED · THIS MACHINE"
        case .connecting, .discovering:
            return "LOOKING FOR YOUR CENTURION"
        case .awaitingApproval:
            return "WAITING FOR YOUR APPROVAL"
        case .error:
            return "OFFLINE · TAP TO RECONNECT"
        case .disconnected:
            return "NOT CONNECTED · TAP TO PAIR"
        }
    }

    // MARK: - Thread

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SignumTheme.Metrics.messageSpacing) {
                    if let issue = connectionIssue {
                        connectionIssueCard(issue)
                            .id("signum-connection-issue")
                    }

                    if messages.isEmpty && !isSending {
                        emptyState
                    }

                    ForEach(messages) { message in
                        SignumMessageRow(
                            message: message,
                            centurionName: identity.name,
                            onCopy: copy,
                            onRetry: message.role == .centurion ? { retry() } : nil
                        )
                        .id(message.id)
                    }

                    ForEach(systemEntries) { entry in
                        SignumSystemRow(entry: entry)
                            .id(entry.id)
                    }

                    if isRunningCommand {
                        SignumSystemRow(
                            entry: SignumSystemEntry(
                                command: "running",
                                lines: ["Asking your Centurion…"],
                                failed: false
                            )
                        )
                        .id("signum-command-running")
                    }

                    if isSending {
                        inFlight
                            .id("signum-in-flight")
                    }

                    if let sendError {
                        errorCard(sendError)
                            .id("signum-error")
                    }

                    Color.clear.frame(height: 1).id("signum-bottom")
                }
                .padding(.horizontal, SignumTheme.Metrics.screenPadding)
                .padding(.top, 20)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in scroll(proxy, animated: true) }
            .onChange(of: connectionManager.streamingAssistantText) { _, _ in
                scroll(proxy, animated: false)
            }
            .onChange(of: isSending) { _, _ in scroll(proxy, animated: true) }
        }
    }

    /// The reason the link is down, in the Brain's own words.
    ///
    /// The header can only carry a status; the actual message ("your pairing code
    /// could not be verified", "this Centurion's key has changed") used to be
    /// thrown away, which left the owner staring at "Offline" with no cause.
    private var connectionIssue: String? {
        switch connectionManager.connectionState {
        case .error(let message): return message
        case .awaitingApproval(let message): return message
        default: return nil
        }
    }

    private func connectionIssueCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NOT LINKED")
                .font(SignumTheme.mono(9.5, .semibold))
                .tracking(1.3)
                .foregroundStyle(SignumTheme.goldDeep)

            Text(message)
                .font(SignumTheme.ui(14))
                .foregroundStyle(SignumTheme.ink)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if connectionManager.serverIdentityChanged {
                    Button("Trust this Centurion again") {
                        Haptics.mediumTap()
                        connectionManager.forgetTrustedServerIdentityAndReconnect()
                    }
                    .font(SignumTheme.ui(13, .medium))
                    .foregroundStyle(SignumTheme.cream)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(SignumTheme.ink))
                } else {
                    Button("Try again") {
                        Haptics.lightTap()
                        connectionManager.reconnect()
                    }
                    .font(SignumTheme.ui(13, .medium))
                    .foregroundStyle(SignumTheme.cream)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(SignumTheme.ink))

                    Button("Pair") {
                        Haptics.lightTap()
                        showConnect = true
                    }
                    .font(SignumTheme.ui(13, .medium))
                    .foregroundStyle(SignumTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .overlay(
                        Capsule().stroke(SignumTheme.hairStrong, lineWidth: 1)
                    )
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SignumTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SignumTheme.hair, lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            SignumMark(size: 54, starOpacity: 0.16)
                .padding(.bottom, 6)

            Text(identity.name)
                .font(SignumTheme.serif(40))
                .foregroundStyle(SignumTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            Text("Ask me anything. Everything you say stays on your machine.")
                .font(SignumTheme.ui(16))
                .foregroundStyle(SignumTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if !isLinked {
                Button {
                    showConnect = true
                } label: {
                    Text("Connect to your Centurion")
                        .font(SignumTheme.ui(14, .medium))
                        .foregroundStyle(SignumTheme.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .overlay(
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .stroke(SignumTheme.hairStrong, lineWidth: 1)
                        )
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 28)
    }

    /// The live turn: the working line first, then the words as they arrive.
    private var inFlight: some View {
        VStack(alignment: .leading, spacing: 10) {
            SignumWorkLine(hint: connectionManager.turnActivityHint)

            let streamed = connectionManager.streamingAssistantText
            if !streamed.isEmpty {
                Text(streamed)
                    .font(SignumTheme.ui(16))
                    .foregroundStyle(SignumTheme.ink.opacity(0.9))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let pending = connectionManager.pendingToolApproval {
                approvalCard(pending)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Tool approval, rendered from `PendingToolApproval`'s own choice list so the
    /// app never invents a vocabulary the Brain does not use.
    private func approvalCard(_ pending: PendingToolApproval) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NEEDS YOUR APPROVAL")
                .font(SignumTheme.mono(9.5, .semibold))
                .tracking(1.3)
                .foregroundStyle(SignumTheme.goldDeep)

            Text(pending.description.isEmpty ? pending.command : pending.description)
                .font(SignumTheme.ui(14))
                .foregroundStyle(SignumTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(pending.choices, id: \.self) { choice in
                    let isDeny = choice.lowercased().contains("deny")
                    Button {
                        Haptics.mediumTap()
                        Task { try? await connectionManager.respondToToolApproval(choice: choice) }
                    } label: {
                        Text(choice.capitalized)
                            .font(SignumTheme.ui(13, .medium))
                            .foregroundStyle(isDeny ? SignumTheme.ink : SignumTheme.cream)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background { approvalButtonBackground(isDeny: isDeny) }
                    }
                }
            }
        }
        .padding(14)
        .background(SignumTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SignumTheme.hair, lineWidth: 1)
        )
    }

    /// Two shapes, two fills — kept out of the button's own modifier chain so
    /// the conditional never has to be erased to AnyView (which rebuilds the
    /// whole subtree on every state change).
    @ViewBuilder
    private func approvalButtonBackground(isDeny: Bool) -> some View {
        if isDeny {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .stroke(SignumTheme.hairStrong, lineWidth: 1)
        } else {
            Capsule().fill(SignumTheme.ink)
        }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(SignumTheme.ui(14))
                .foregroundStyle(SignumTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if lastFailed != nil {
                Button {
                    retry()
                } label: {
                    Text("Try again")
                        .font(SignumTheme.ui(13, .medium))
                        .foregroundStyle(SignumTheme.goldDeep)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SignumTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SignumTheme.hair, lineWidth: 1)
        )
    }

    // MARK: - Composer

    private var composerArea: some View {
        VStack(spacing: 0) {
            // The palette sits above the field, not over it — the owner can see what they
            // are choosing and what they were typing at the same time.
            if showsPalette {
                SignumCommandPalette(query: draft) { command in
                    pick(command)
                }
                .padding(.bottom, 8)
                .transition(.opacity)
            }

            Divider().overlay(SignumTheme.hair)

            HStack(alignment: .bottom, spacing: 10) {
                TextField(placeholder, text: $draft, axis: .vertical)
                    .font(SignumTheme.ui(16))
                    .foregroundStyle(SignumTheme.ink)
                    .lineLimit(1...6)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.vertical, 8)
                    .disabled(!isLinked)

                if !isLinked {
                    Button("Connect") { showConnect = true }
                        .font(SignumTheme.ui(13, .medium))
                        .foregroundStyle(SignumTheme.goldDeep)
                        .padding(.bottom, 8)
                }

                if isSending {
                    Button(action: stop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(SignumTheme.ink)
                            .frame(width: 34, height: 34)
                            .background(SignumTheme.hair)
                            .clipShape(Circle())
                    }
                    .padding(.bottom, 4)
                    .accessibilityLabel("Stop")
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(canSend ? SignumTheme.cream : SignumTheme.muted)
                            .frame(width: 34, height: 34)
                            .background(canSend ? SignumTheme.ink : SignumTheme.hair)
                            .clipShape(Circle())
                    }
                    .disabled(!canSend)
                    .padding(.bottom, 4)
                    .accessibilityLabel("Send")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(SignumTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: SignumTheme.Metrics.composerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SignumTheme.Metrics.composerRadius, style: .continuous)
                    .stroke(SignumTheme.hair, lineWidth: 1)
            )
            .padding(.horizontal, SignumTheme.Metrics.screenPadding)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .background(SignumTheme.cream)
    }

    private var placeholder: String {
        isLinked ? "Ask \(identity.name)" : "Not connected"
    }

    /// A leading `/` with no space yet means the owner is naming a command, not writing one.
    private var showsPalette: Bool {
        guard draft.hasPrefix("/") else { return false }
        return !draft.dropFirst().contains(" ")
    }

    private var canSend: Bool {
        isLinked && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    // MARK: - Actions

    private func resolveConversation() {
        if conversationId != nil { return }
        if let current = messageService.currentConversation {
            conversationId = current.id
            return
        }
        let conv = messageService.findOrCreateConversation(
            for: .standalone(title: Self.newConversationTitle())
        )
        conversationId = conv.id
    }

    private func startNewConversation() {
        let conv = messageService.findOrCreateConversation(
            for: .standalone(title: Self.newConversationTitle())
        )
        conversationId = conv.id
        sendError = nil
        draft = ""
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // A command is not a message. It never reaches the model, never becomes history,
        // and never costs a turn.
        if text.hasPrefix("/") {
            draft = ""
            composerFocused = false
            runCommandLine(text)
            return
        }

        guard isLinked else { return }

        Haptics.messageSent()
        draft = ""
        sendError = nil
        didCancelTurn = false
        lastFailed = text
        isSending = true
        composerFocused = false
        turnToken += 1
        let token = turnToken

        resolveConversation()
        guard let conversation else {
            isSending = false
            return
        }

        Task {
            do {
                _ = try await messageService.sendMessage(text, in: conversation.context)
            } catch {
                guard token == turnToken else { return }
                if didCancelTurn {
                    didCancelTurn = false
                } else {
                    Haptics.error()
                    sendError = connectionManager.friendlyRemoteError(error)
                }
            }
            if token == turnToken { isSending = false }
        }
    }

    /// Abandon the turn. The request cannot be recalled from the Brain, but the
    /// app stops waiting on it and the thread stops claiming work is happening.
    private func stop() {
        Haptics.mediumTap()
        didCancelTurn = true
        turnToken += 1
        connectionManager.cancelInFlightChat()
        isSending = false
        sendError = nil
    }

    private func retry() {
        guard let text = lastFailed, let conversation else { return }
        // The failed send already left the question in the thread — drop it so a
        // retry does not post the same question twice.
        messageService.discardUnansweredUserMessage(text, in: conversation.id)
        draft = text
        sendError = nil
        send()
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        Haptics.lightTap()
    }

    // MARK: - Commands

    /// Resolve a typed slash line to a catalogue entry and run it.
    ///
    /// An unknown command does not go to the Brain as chat: it warns and stays in the
    /// field, so a mistyped `/staus` cannot accidentally become a question.
    private func runCommandLine(_ text: String) {
        let body = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        let name = body.split(separator: " ").first.map(String.init)?.lowercased() ?? ""

        if let command = SignumCommand.catalogue.first(where: { $0.name == name }) {
            pick(command)
            return
        }

        if let refused = legacyCommandHint(name) {
            appendSystem(SignumSystemEntry(command: name, lines: [refused], failed: true))
            return
        }

        appendSystem(
            SignumSystemEntry(
                command: name.isEmpty ? "command" : name,
                lines: [
                    "No such command.",
                    "Available: " + SignumCommand.catalogue.map(\.display).joined(separator: "  "),
                ],
                failed: true
            )
        )
    }

    /// Commands Telegram accepted that this surface deliberately does not. Saying why beats
    /// saying nothing — the owner learns the machine is fine, the door is just closed here.
    private func legacyCommandHint(_ name: String) -> String? {
        switch name {
        case "model":
            return "/model is set on the desk. Changing the model from a phone can leave a Centurion answering on a credential it cannot test."
        case "restart", "update":
            return "/\(name) runs at the desk, where a failure can be recovered."
        case "quit", "quit.":
            return "There is nothing to quit here — the Brain is not a terminal."
        default:
            return nil
        }
    }

    private func pick(_ command: SignumCommand) {
        Haptics.lightTap()
        draft = ""
        switch command.action {
        case .newConversation:
            startNewConversation()
        case .stopTurn:
            if isSending { stop() }
        case .retryTurn:
            retry()
        case .openConversations:
            showConversations = true
        case .showHelp:
            appendSystem(
                SignumSystemEntry(
                    command: "help",
                    lines: SignumCommand.catalogue.map { "\($0.display) — \($0.summary)" },
                    failed: false
                )
            )
        case .brain(let name):
            Task { @MainActor in await runBrainCommand(name) }
        }
    }

    private func runBrainCommand(_ name: String) async {
        isRunningCommand = true
        defer { isRunningCommand = false }
        do {
            let payload = try await connectionManager.runSlashCommand(name)
            let lines = Self.lines(from: payload)
            let ok = (payload["ok"] as? Bool) ?? !lines.isEmpty
            appendSystem(SignumSystemEntry(command: name, lines: lines, failed: !ok))
        } catch {
            appendSystem(
                SignumSystemEntry(
                    command: name,
                    lines: [connectionManager.friendlyRemoteError(error)],
                    failed: true
                )
            )
        }
    }

    /// Prefer the Brain's structured `lines`; fall back to its `text`, then to the raw
    /// message. Never invent output for a command that returned nothing.
    private static func lines(from payload: [String: Any]) -> [String] {
        if let lines = payload["lines"] as? [String], !lines.isEmpty {
            return lines
        }
        if let text = payload["text"] as? String, !text.isEmpty {
            return text.components(separatedBy: "\n")
        }
        if let message = payload["message"] as? String, !message.isEmpty {
            return [message]
        }
        return ["No output returned."]
    }

    private func appendSystem(_ entry: SignumSystemEntry) {
        systemEntries.append(entry)
        Haptics.lightTap()
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        let action = { proxy.scrollTo("signum-bottom", anchor: .bottom) }
        if animated {
            withAnimation(Motion.standard) { action() }
        } else {
            action()
        }
    }

    private static func newConversationTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM · HH:mm"
        return "Chat · \(formatter.string(from: Date()))"
    }
}
