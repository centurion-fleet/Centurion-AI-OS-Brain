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
    @State private var copied = false
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
                onSelect: { id in
                    conversationId = id
                    showConversations = false
                    Haptics.lightTap()
                },
                onNew: {
                    startNewConversation()
                    showConversations = false
                }
            )
            .environmentObject(messageService)
            .environmentObject(connectionManager)
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
            await identity.refresh(using: connectionManager)
        }
        .onChange(of: connectionManager.connectionState) { _, _ in
            Task { await identity.refresh(using: connectionManager) }
        }
    }

    // MARK: - Header — the name in the hero spot

    private var header: some View {
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

    private var statusLine: String {
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
        guard !text.isEmpty, isLinked else { return }

        Haptics.messageSent()
        draft = ""
        sendError = nil
        lastFailed = text
        isSending = true
        composerFocused = false

        resolveConversation()
        guard let conversation else {
            isSending = false
            return
        }

        Task {
            do {
                _ = try await messageService.sendMessage(text, in: conversation.context)
            } catch {
                Haptics.error()
                sendError = connectionManager.friendlyRemoteError(error)
            }
            isSending = false
        }
    }

    private func retry() {
        guard let text = lastFailed else { return }
        draft = text
        sendError = nil
        send()
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
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
