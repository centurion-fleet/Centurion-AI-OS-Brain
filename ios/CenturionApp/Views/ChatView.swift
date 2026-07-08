import SwiftUI

/// Unified chat view — used both in the Chat tab (global stream)
/// and as a context-aware sheet from Mission Control.
///
/// In **stream mode** (no contextFilter): shows every message chronologically
/// with mission-context badges.
///
/// In **context mode** (contextFilter set): shows only messages for one conversation,
/// hiding badges (the context is already obvious).
struct ChatView: View {
    let conversation: Conversation?

    @EnvironmentObject private var messageService: MessageService
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var messageText = ""
    @State private var isSending = false
    @FocusState private var isFocused: Bool

    /// For GROK-style hamburger navigation
    let onSwitchConversation: ((Conversation) -> Void)?

    init(conversation: Conversation? = nil, onSwitchConversation: ((Conversation) -> Void)? = nil) {
        self.conversation = conversation
        self.onSwitchConversation = onSwitchConversation
    }

    var body: some View {
        VStack(spacing: 0) {
            if let conversation = conversation {
                // Context header — shows where this conversation lives in the mission hierarchy
                contextHeader(conversation: conversation)
            }

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Spacing.sm) {
                        if let conversation = conversation {
                            // Context mode — single conversation messages
                            let msgs = messageService.messages(for: conversation.id)
                            if msgs.isEmpty {
                                emptyChatState(context: conversation.context)
                                    .padding(.top, Spacing.xxl)
                            } else {
                                ForEach(msgs) { message in
                                    MessageRow(message: message, showContext: false)
                                        .id(message.id)
                                }
                            }
                        } else {
                            // Stream mode — ALL messages chronologically with context badges
                            VStack(spacing: 0) {
                                // Centurion Pulse header
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: "waveform.path.ecg")
                                        .font(.caption)
                                        .foregroundColor(ColorTheme.accent())
                                    Text("Centurion Pulse")
                                        .font(.system(size: 13, weight: .semibold, design: .default))
                                        .foregroundColor(ColorTheme.accent())
                                    Spacer()
                                    Text("\(messageService.allMessages.count)")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundColor(ColorTheme.mutedText())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(ColorTheme.border())
                                        .clipShape(Capsule())
                                }
                                .padding(.horizontal, Spacing.md)
                                .padding(.top, Spacing.sm)
                                .padding(.bottom, Spacing.xxs)

                                if messageService.allMessages.isEmpty {
                                emptyGlobalStream
                                    .padding(.top, Spacing.xxl)
                            } else {
                                // Date grouping headers
                                let grouped = groupByDate(messageService.allMessages)
                                ForEach(grouped.keys.sorted(by: >), id: \.self) { date in
                                    Section {
                                        ForEach(grouped[date]!) { message in
                                            MessageRow(message: message, showContext: true)
                                                .id(message.id)
                                        }
                                    } header: {
                                        dateHeader(date)
                                    }
                                }
                            }
                        }
                    }
                }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messageService.allMessages.count) { _, _ in
                    scrollToLast(proxy)
                }
                .onAppear {
                    scrollToLast(proxy)
                }
            }

            // Input bar
            inputBar
        }
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
            Image(systemName: conversation.context.isStandalone ? "lock.fill" : "target")
                .font(.system(size: 8))
                .foregroundColor(ColorTheme.accent())
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(ColorTheme.accent().opacity(0.05))
    }

    // MARK: - Empty States

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

    private var emptyGlobalStream: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "message.fill")
                .font(.system(size: 40))
                .foregroundColor(ColorTheme.mutedText())

            Text("No messages yet")
                .font(.headline)
                .foregroundColor(ColorTheme.primaryText())

            Text("Start a conversation from Mission Control or send a message below.")
                .font(.subheadline)
                .foregroundColor(ColorTheme.mutedText())
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Date Header

    private func dateHeader(_ date: Date) -> some View {
        HStack(spacing: Spacing.xs) {
            Rectangle()
                .fill(ColorTheme.border())
                .frame(height: 0.5)
            Text(date, style: .date)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ColorTheme.mutedText())
                .padding(.horizontal, Spacing.xs)
            Rectangle()
                .fill(ColorTheme.border())
                .frame(height: 0.5)
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(ColorTheme.border())
                .frame(height: 0.5)

            HStack(spacing: Spacing.sm) {
                HStack(spacing: 0) {
                    TextField(
                        conversation != nil
                            ? "Message about \(conversation!.displayTitle)…"
                            : "Message your Centurion…",
                        text: $messageText
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($isFocused)
                    .disabled(isSending)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                }
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

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        Haptics.messageSent()
        messageText = ""
        isSending = true

        Task {
            do {
                if let conversation = conversation {
                    try await messageService.sendMessage(text, in: conversation.context)
                } else {
                    // When sending from the global stream, create a standalone conversation
                    let context = ConversationContext.standalone(title: "Quick Chat")
                    try await messageService.sendMessage(text, in: context)
                }
            } catch {
                Haptics.error()
            }
            isSending = false
        }
    }

    // MARK: - Helpers

    private func scrollToLast(_ proxy: ScrollViewProxy) {
        let messages = conversation != nil
            ? messageService.messages(for: conversation!.id)
            : messageService.allMessages
        if let last = messages.last {
            withAnimation(Motion.heavy) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func groupByDate(_ messages: [Message]) -> [Date: [Message]] {
        Dictionary(grouping: messages) { message in
            Calendar.current.startOfDay(for: message.timestamp)
        }
    }
}

// MARK: - Message Row

/// A single message in the stream — either in context mode (badge hidden)
/// or stream mode (badge shows mission level).
struct MessageRow: View {
    let message: Message
    let showContext: Bool

    @EnvironmentObject private var messageService: MessageService
    @State private var isAppeared = false

    private var conversation: Conversation? {
        messageService.conversations.first { $0.id == message.conversationId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Context badge (only in stream mode)
            if showContext, let conv = conversation {
                HStack(spacing: 4) {
                    Image(systemName: conv.icon)
                        .font(.system(size: 8))
                    Text(conv.contextPath)
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(conv.missionBadge.color)
                .padding(.leading, 4)
            }

            // Message bubble
            HStack(alignment: .bottom, spacing: Spacing.xs) {
                if message.role == .user { Spacer(minLength: 48) }

                if message.role == .centurion {
                    centurionAvatar
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
                .offset(y: isAppeared ? 0 : 12)
                .opacity(isAppeared ? 1 : 0)

                if message.role == .centurion { Spacer(minLength: 48) }

                if message.role == .user {
                    userAvatar
                }
            }
        }
        .onAppear {
            withAnimation(Motion.appear.delay(Double.random(in: 0.05...0.15))) {
                isAppeared = true
            }
        }
    }

    private var centurionAvatar: some View {
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

    private var userAvatar: some View {
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

// MARK: - Context Extensions

extension ConversationContext {
    var isStandalone: Bool {
        if case .standalone = self { return true }
        return false
    }
}
