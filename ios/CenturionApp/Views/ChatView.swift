import SwiftUI

/// Clean chat interface with a pull-down conversation tray.
/// Tap Conversations under the page title to open the tray.
struct ChatView: View {
    /// Initialize with an optional conversation to open immediately.
    /// Pass nil (default) for the clean empty state.
    init(conversation: Conversation? = nil, usesPageChrome: Bool = true) {
        _selectedConversation = State(initialValue: conversation)
        self.usesPageChrome = usesPageChrome
    }

    var usesPageChrome: Bool = true

    @EnvironmentObject private var messageService: MessageService
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var dataMode: AppDataMode
    @State private var messageText = ""
    @State private var isSending = false
    @State private var sendError: String?
    @FocusState private var isFocused: Bool

    /// The currently selected conversation (nil = clean empty state)
    @State private var selectedConversation: Conversation?

    /// Pull-down tray state
    @State private var showTray = false

    var body: some View {
        Group {
            if usesPageChrome {
                TabPageChrome(title: "Chat") {
                    conversationTrayTrigger
                        .padding(.horizontal, Spacing.sm)
                        .padding(.bottom, Spacing.xs)
                } content: {
                    chatContent
                }
            } else {
                VStack(spacing: 0) {
                    conversationTrayTrigger
                    chatContent
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            if dataMode.showsDemoContent && !messageService.conversations.isEmpty {
                DemoDataBanner()
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.xs)
            }

            if connectionManager.connectionState != .connected {
                offlineBanner
            }

            if let sendError {
                errorBanner(sendError)
            }

            if showTray {
                conversationTray
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let conversation = selectedConversation {
                contextHeader(conversation: conversation)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: Spacing.sm) {
                            let msgs = messageService.messages(for: conversation.id)
                            if msgs.isEmpty {
                                emptyChatState(context: conversation.context)
                                    .padding(.top, Spacing.xxl)
                            } else {
                                ForEach(msgs) { message in
                                    messageRow(message, showContext: false)
                                        .id(message.id)
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                    }
                    .onChange(of: messageService.allMessages.count) { _, _ in
                        scrollToLast(proxy, conversation: conversation)
                    }
                    .onAppear {
                        scrollToLast(proxy, conversation: conversation)
                    }
                }
            } else {
                emptyState
            }

            inputBar
        }
        .background(ColorTheme.background())
    }

    // MARK: - Conversation Tray Trigger

    private var conversationTrayTrigger: some View {
        Button(action: {
            Haptics.lightTap()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                showTray.toggle()
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.caption)
                    .foregroundColor(ColorTheme.accent())
                Text("Conversations")
                    .font(.caption.weight(.semibold))
                Image(systemName: showTray ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundColor(ColorTheme.mutedText())

                if let conv = selectedConversation {
                    Text(conv.displayTitle)
                        .font(.caption2)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ColorTheme.accent().opacity(0.1))
                        .clipShape(Capsule())
                }

                Spacer()

                if connectionManager.connectionState == .connected {
                    StatusDot(isConnected: true)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pull-Down Conversation Tray

    private var conversationTray: some View {
        VStack(spacing: 0) {
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Mission conversations
                    let missionConvs = messageService.conversations.filter { !$0.context.isStandalone }
                    if !missionConvs.isEmpty {
                        traySectionHeader("FROM YOUR MISSION", icon: "target")
                        ForEach(missionConvs) { conv in
                            trayRow(conv)
                        }
                    }

                    // Standalone conversations
                    let standaloneConvs = messageService.conversations.filter { $0.context.isStandalone }
                    if !standaloneConvs.isEmpty {
                        traySectionHeader("CHATS", icon: "message.fill")
                        ForEach(standaloneConvs) { conv in
                            trayRow(conv)
                        }
                    }

                    if messageService.conversations.isEmpty {
                        VStack(spacing: Spacing.sm) {
                            Image(systemName: "message.fill")
                                .font(.system(size: 20))
                                .foregroundColor(ColorTheme.mutedText())
                            Text("No conversations yet")
                                .font(.subheadline)
                                .foregroundColor(ColorTheme.mutedText())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xl)
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
            .frame(maxHeight: 320)

            Divider()
        }
        .background(ColorTheme.surface())
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func traySectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(ColorTheme.accent())
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .default))
                .foregroundColor(ColorTheme.mutedText())
                .textCase(.uppercase)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.xxs)
    }

    private func trayRow(_ conversation: Conversation) -> some View {
        Button(action: {
            Haptics.mediumTap()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                selectedConversation = conversation
                showTray = false
            }
        }) {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(conversation.missionBadge.color.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: conversation.icon)
                        .font(.system(size: 11))
                        .foregroundColor(conversation.missionBadge.color)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(conversation.displayTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(ColorTheme.primaryText())

                    if let lastMsg = messageService.messages(for: conversation.id).last {
                        Text(lastMsg.content)
                            .font(.system(size: 11))
                            .foregroundColor(ColorTheme.mutedText())
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(conversation.lastActive, style: .relative)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(ColorTheme.mutedText())
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(selectedConversation?.id == conversation.id ? ColorTheme.accent().opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Context Header

    private func contextHeader(conversation: Conversation) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: conversation.icon)
                .font(.caption)
                .foregroundColor(conversation.missionBadge.color)
            Text(conversation.contextPath)
                .font(.caption)
                .foregroundColor(conversation.missionBadge.color)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(ColorTheme.accent().opacity(0.05))
    }

    // MARK: - Status Banners

    private var offlineBanner: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "wifi.slash")
                .foregroundColor(ColorTheme.mutedText())
            Text("Not connected — link your Centurion in the Connect tab to send messages.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTheme.surface())
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.circle")
                .foregroundColor(ColorTheme.error())
            Text(message)
                .font(.caption)
                .foregroundColor(ColorTheme.primaryText())
            Spacer()
            Button("Dismiss") { sendError = nil }
                .font(.caption)
                .foregroundColor(ColorTheme.accent())
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(ColorTheme.error().opacity(0.08))
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Spacer()

            Image(systemName: "message.fill")
                .font(.system(size: 40))
                .foregroundColor(ColorTheme.accent().opacity(0.45))

            Text("All messages from your Centurion appear here.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)

            Text("Tap Conversations above to open a thread.")
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText().opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)

            Spacer()
        }
        .frame(maxWidth: 428)
    }

    private func emptyChatState(context: ConversationContext) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundColor(ColorTheme.mutedText())

            Text("Chat about \(context.displayTitle)")
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText())
                .multilineTextAlignment(.center)

            Text("Messages here appear in the full chat stream too.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(ColorTheme.border())
                .frame(height: 0.5)

            HStack(spacing: Spacing.sm) {
                TextField(
                    selectedConversation != nil
                        ? "Message about \(selectedConversation!.displayTitle)…"
                        : "Message your Centurion…",
                    text: $messageText
                )
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isFocused)
                .disabled(isSending || connectionManager.connectionState != .connected)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(ColorTheme.chatInput())
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isFocused ? ColorTheme.accent().opacity(0.4) : ColorTheme.border(), lineWidth: 1)
                )
                .animation(Motion.light, value: isFocused)

                if isSending {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 40, height: 40)
                } else {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(
                                messageText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? ColorTheme.mutedText()
                                : ColorTheme.accent()
                            )
                    }
                    .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .animation(Motion.light, value: messageText)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(.ultraThinMaterial)
        }
        .padding(.bottom, Spacing.lg)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        sendError = nil
        Haptics.messageSent()
        messageText = ""
        isSending = true

        // Select the conversation before the async send so the user's message
        // stays visible while waiting for the Centurion response.
        let context: ConversationContext
        if let selected = selectedConversation {
            context = selected.context
        } else {
            context = ConversationContext.standalone(title: "Quick Chat")
            selectedConversation = messageService.findOrCreateConversation(for: context)
        }

        Task {
            do {
                let conversation = try await messageService.sendMessage(text, in: context)
                selectedConversation = conversation
                withAnimation(Motion.standard) {
                    showTray = false
                }
            } catch {
                Haptics.error()
                sendError = error.localizedDescription
            }
            isSending = false
        }
    }

    private func scrollToLast(_ proxy: ScrollViewProxy, conversation: Conversation) {
        let msgs = messageService.messages(for: conversation.id)
        if let last = msgs.last {
            withAnimation(Motion.heavy) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Message Row

    private func messageRow(_ message: Message, showContext: Bool) -> some View {
        HStack(alignment: .bottom, spacing: Spacing.xs) {
        if message.role == .user { Spacer(minLength: 48) }

        if message.role == .centurion {
            ZStack {
                Circle()
                    .fill(ColorTheme.accent().opacity(0.15))
                    .frame(width: 28, height: 28)
                Circle()
                    .fill(ColorTheme.accent())
                    .frame(width: 8, height: 8)
            }
            .padding(.bottom, 4)
        }

        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 3) {
            if message.role == .centurion {
                Text("Centurion")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ColorTheme.accent())
                    .padding(.horizontal, 4)
            }

            Text(message.content)
                .font(.system(size: 16))
                .foregroundColor(ColorTheme.primaryText())
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(message.role == .user
                    ? ColorTheme.accent().opacity(0.12)
                    : ColorTheme.surface())
                .clipShape(BubbleShape(role: message.role))
                .overlay(
                    BubbleShape(role: message.role)
                        .stroke(ColorTheme.border(), lineWidth: message.role == .user ? 0 : 0.5)
                )
        }

        if message.role == .centurion { Spacer(minLength: 48) }

        if message.role == .user {
            ZStack {
                Circle()
                    .fill(ColorTheme.accent().opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: "person.fill")
                    .font(.system(size: 11))
                    .foregroundColor(ColorTheme.accent())
            }
            .padding(.bottom, 4)
        }
    }
}

}

// MARK: - Bubble Shape

struct BubbleShape: Shape {
    let role: MessageRole

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        var path = Path()

        switch role {
        case .user:
            path = Path(roundedRect: rect,
                       cornerSize: CGSize(width: radius, height: radius),
                       style: .continuous)
            path.addRect(CGRect(x: rect.maxX - radius, y: rect.maxY - radius,
                               width: radius, height: radius))
        case .centurion:
            path = Path(roundedRect: rect,
                       cornerSize: CGSize(width: radius, height: radius),
                       style: .continuous)
            path.addRect(CGRect(x: rect.minX, y: rect.maxY - radius,
                               width: radius, height: radius))
        case .system:
            path = Path(roundedRect: rect, cornerRadius: radius)
        }

        return path
    }
}
