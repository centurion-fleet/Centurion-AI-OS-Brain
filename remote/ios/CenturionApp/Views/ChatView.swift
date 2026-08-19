import SwiftUI

/// Chat — transcript first. Conversations tray is the only chrome above messages.
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
    @EnvironmentObject private var missionStore: MissionStore
    @EnvironmentObject private var planStore: PlanStore
    @State private var messageText = ""
    @State private var isSending = false
    @State private var sendError: String?
    @State private var lastFailedMessage: String?
    @State private var showRecoverySheet = false
    /// Chat = typed reply (not voice). Propose first = draft work and stop for Focus review.
    @State private var proposeFirst = false
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    /// The currently selected conversation (nil = clean empty state)
    @State private var selectedConversation: Conversation?

    /// Pull-down tray state
    @State private var showTray = false
    @State private var showRenameAlert = false
    @State private var renameTarget: Conversation?
    @State private var renameDraft = ""

    var body: some View {
        Group {
            if usesPageChrome {
                NavigationStack {
                    VStack(spacing: 0) {
                        conversationTrayTrigger
                        chatContent
                    }
                    .background(
                        ZStack {
                            ColorTheme.background()
                            ColorTheme.atmosphericVeil()
                                .ignoresSafeArea()
                        }
                    )
                    .toolbar(.hidden, for: .navigationBar)
                }
            } else {
                VStack(spacing: 0) {
                    conversationTrayTrigger
                    chatContent
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if usesPageChrome, selectedConversation == nil, let current = messageService.currentConversation {
                selectedConversation = current
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .centurionOpenConversation)) { notification in
            guard usesPageChrome, let id = notification.object as? UUID else { return }
            if let conv = messageService.conversations.first(where: { $0.id == id }) {
                selectedConversation = conv
                showTray = false
            }
        }
        .alert("Rename topic", isPresented: $showRenameAlert) {
            TextField("Name", text: $renameDraft)
            Button("Cancel", role: .cancel) {
                renameTarget = nil
            }
            Button("Save") {
                guard let target = renameTarget else { return }
                Task { @MainActor in
                    let updated = await messageService.renameHostTopic(target, title: renameDraft)
                    if selectedConversation?.id == target.id {
                        selectedConversation = updated
                    }
                    renameTarget = nil
                }
            }
        } message: {
            Text("Choose a name for this conversation topic.")
        }
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            if dataMode.showsDemoContent {
                DemoDataBanner()
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.xs)
            }

            if !connectionManager.isCryptoChatReady {
                offlineBanner
            } else if connectionManager.isHydratingAfterLink {
                hydratingBanner
            }

            if let sendError {
                if connectionManager.llmHealth.needsAttention,
                   !Self.looksLikePipeWait(sendError) {
                    llmErrorBanner(sendError)
                } else {
                    errorBanner(sendError)
                }
            }

            if showTray {
                conversationTray
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Group {
                if selectedConversation == nil {
                    transcript(messages: messageService.allMessages, showContext: true)
                } else if let conversation = selectedConversation {
                    contextHeader(conversation: conversation)
                    transcript(
                        messages: messageService.messages(for: conversation.id),
                        showContext: false,
                        conversation: conversation
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let approval = connectionManager.pendingToolApproval {
                toolApprovalCard(approval)
            }
            inputBar
        }
        .background(ColorTheme.background())
        .sheet(isPresented: $showRecoverySheet) {
            ThinkingRecoverySheet(initialMessage: sendError ?? "Your Sovereign's thinking service needs attention.")
                .environmentObject(connectionManager)
        }
    }

    private func transcript(
        messages: [Message],
        showContext: Bool,
        conversation: Conversation? = nil
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.md) {
                    if connectionManager.isHydratingAfterLink {
                        hydratingChatNotice
                            .padding(.top, Spacing.lg)
                            .id("hydrating-notice")
                    } else if messages.isEmpty && !(isSending && !connectionManager.streamingAssistantText.isEmpty) {
                        if let conversation {
                            emptyChatState(context: conversation.context)
                                .padding(.top, Spacing.xl)
                        } else {
                            emptyState
                                .padding(.top, Spacing.xl)
                        }
                    } else {
                        ForEach(messages) { message in
                            messageRow(message, showContext: showContext)
                                .id(message.id)
                        }
                    }
                    if isSending, !connectionManager.streamingAssistantText.isEmpty {
                        streamingDraftRow(connectionManager.streamingAssistantText)
                            .id("streaming-draft")
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .simultaneousGesture(
                TapGesture().onEnded {
                    dismissComposer()
                }
            )
            .onChange(of: messages.count) { _, _ in
                if let conversation {
                    scrollToLast(proxy, conversation: conversation)
                } else {
                    scrollToLastInStream(proxy)
                }
            }
            .onChange(of: connectionManager.streamingAssistantText) { _, _ in
                withAnimation(Motion.light) {
                    proxy.scrollTo("streaming-draft", anchor: .bottom)
                }
            }
            .onAppear {
                if let conversation {
                    scrollToLast(proxy, conversation: conversation)
                } else {
                    scrollToLastInStream(proxy)
                }
            }
        }
    }

    // MARK: - Conversation Tray Trigger

    /// Closes the composer so the Chat / Focus / Collab / You tab bar is visible again.
    private func dismissComposer() {
        isFocused = false
    }

    private var conversationTrayTrigger: some View {
        HStack(spacing: Spacing.sm) {
            if usesPageChrome && isFocused {
                Button {
                    Haptics.lightTap()
                    dismissComposer()
                } label: {
                    Text("Done")
                        .font(.body.weight(.semibold))
                        .foregroundColor(ColorTheme.accent())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close keyboard and show tabs")
                .accessibilityHint("Reveals Chat, Focus, Collab, and You at the bottom of the screen.")
            }

            Button(action: {
                Haptics.lightTap()
                dismissComposer()
                let opening = !showTray
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    showTray.toggle()
                }
                if opening, !connectionManager.isHydratingAfterLink {
                    Task { @MainActor in
                        _ = await messageService.syncHostTopicsFromBrain()
                    }
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
                    } else {
                        Text("All Chat")
                            .font(.caption2)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ColorTheme.accent().opacity(0.1))
                            .clipShape(Capsule())
                    }

                    Spacer(minLength: 8)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                selectedConversation.map { "Conversations, \($0.displayTitle)" } ?? "Conversations, All Chat"
            )
            .accessibilityHint("Switch topics. Close the keyboard to reach Focus, Collab, or You.")

            if connectionManager.isCryptoChatReady {
                Button {
                    Haptics.lightTap()
                    dismissComposer()
                    AdrianNavigation.selectTab(AdrianNavigation.collabTab)
                } label: {
                    Image(systemName: "circle.grid.cross")
                        .font(.caption)
                        .foregroundColor(ColorTheme.accent())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Collab")

                StatusDot(
                    isConnected: true,
                    isEncrypted: connectionManager.isChannelEncrypted,
                    needsAttention: !connectionManager.isHydratingAfterLink
                        && connectionManager.llmHealth.needsAttention
                )
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 2)
    }

    // MARK: - Pull-Down Conversation Tray

    private var conversationTray: some View {
        VStack(spacing: 0) {
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    traySectionHeader("Stream", icon: "bubble.left.and.bubble.right")
                    allChatTrayRow()

                    if connectionManager.isCryptoChatReady {
                        Button {
                            Haptics.mediumTap()
                            Task { @MainActor in
                                let created = await messageService.startNewFreeformTopic()
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                                    selectedConversation = created
                                    showTray = false
                                }
                            }
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                ZStack {
                                    Circle()
                                        .fill(ColorTheme.accent().opacity(0.12))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "plus")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(ColorTheme.accent())
                                }
                                Text("New topic")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(ColorTheme.primaryText())
                                Spacer()
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    // Mission conversations
                    let missionConvs = messageService.conversations.filter { !$0.context.isStandalone }
                    if !missionConvs.isEmpty {
                        traySectionHeader("From your mission", icon: "target")
                        ForEach(missionConvs) { conv in
                            trayRow(conv)
                        }
                    }

                    // Standalone conversations
                    let standaloneConvs = messageService.conversations.filter { $0.context.isStandalone }
                    if !standaloneConvs.isEmpty {
                        traySectionHeader("Past conversations", icon: "message.fill")
                        ForEach(standaloneConvs) { conv in
                            trayRow(conv)
                        }
                    }

                    if messageService.conversations.isEmpty {
                        VStack(spacing: Spacing.sm) {
                            Image(systemName: "message.fill")
                                .font(.system(size: 20))
                                .foregroundColor(ColorTheme.mutedText())
                            Text("No conversations yet — start Crypto Chat below")
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
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ColorTheme.accent())
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(ColorTheme.mutedText())
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.xxs)
    }

    private func allChatTrayRow() -> some View {
        Button(action: {
            Haptics.mediumTap()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                selectedConversation = nil
                showTray = false
            }
        }) {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(ColorTheme.accent().opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 11))
                        .foregroundColor(ColorTheme.accent())
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("All Chat")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(ColorTheme.primaryText())
                    Text("Unified Crypto Chat stream with context badges")
                        .font(.system(size: 11))
                        .foregroundColor(ColorTheme.mutedText())
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(selectedConversation == nil ? ColorTheme.accent().opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func trayRow(_ conversation: Conversation) -> some View {
        Button(action: {
            Haptics.mediumTap()
            Task { @MainActor in
                let opened = await messageService.openHostTopic(conversation)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    selectedConversation = opened
                    showTray = false
                }
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
        .contextMenu {
            Button("Rename") {
                renameTarget = conversation
                renameDraft = conversation.displayTitle
                showRenameAlert = true
            }
            Button("Delete", role: .destructive) {
                Task { @MainActor in
                    let id = conversation.id
                    await messageService.deleteHostTopic(conversation)
                    if selectedConversation?.id == id {
                        selectedConversation = messageService.currentConversation
                    }
                }
            }
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
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 6)
        .background(ColorTheme.accent().opacity(0.05))
    }

    // MARK: - Status Banners

    private var hydratingBanner: some View {
        AtmosphericSurface {
            HStack(alignment: .top, spacing: Spacing.sm) {
                ProgressView()
                    .tint(ColorTheme.accent())
                VStack(alignment: .leading, spacing: 4) {
                    Text("Loading mission data. Please wait.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorTheme.primaryText())
                    Text("Chat opens once your missions are on this phone. Stay here — don’t send Hi yet.")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.xs)
        .accessibilityLabel("Loading mission data. Please wait.")
    }

    private var hydratingChatNotice: some View {
        EmptyState(
            icon: "hourglass",
            title: "Loading mission data",
            message: "Please wait. Chat will open when your missions are on this phone."
        )
        .frame(maxWidth: 428)
    }

    private var offlineBanner: some View {
        Button {
            NotificationCenter.default.post(name: .centurionSelectTab, object: AdrianNavigation.youTab)
        } label: {
            AtmosphericSurface {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "wifi.slash")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.mutedText())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pair your Brain to begin")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(ColorTheme.primaryText())
                        Text("Open You to scan the pairing QR and start Crypto Chat.")
                            .font(.caption)
                            .foregroundColor(ColorTheme.mutedText())
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ColorTheme.mutedText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.xs)
        .accessibilityLabel("Pair your Brain to begin. Open You to scan the pairing QR.")
    }

    private func llmErrorBanner(_ message: String) -> some View {
        Button {
            showRecoverySheet = true
        } label: {
            AtmosphericSurface(elevated: true) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.error())
                    Text(message)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(ColorTheme.primaryText())
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(ColorTheme.error().opacity(0.25), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.xs)
        .accessibilityLabel(message)
        .accessibilityHint("Opens the Fix Thinking Service screen")
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
        VStack {
            Spacer()
            if connectionManager.isCryptoChatReady {
                EmptyState(
                    icon: "lock.shield",
                    title: "Crypto Chat",
                    message: "Your private encrypted conversation starts here. Send a message when you’re ready."
                )
            } else {
                EmptyState(
                    icon: "lock.shield",
                    title: "Pair your Brain to begin",
                    message: "Open You and scan the pairing QR to start Crypto Chat — a private encrypted conversation public AIs do not offer.",
                    actionTitle: "Open You",
                    action: {
                        NotificationCenter.default.post(name: .centurionSelectTab, object: AdrianNavigation.youTab)
                    }
                )
            }
            Spacer()
        }
        .frame(maxWidth: 428)
    }

    private func emptyChatState(context: ConversationContext) -> some View {
        let message: String
        if case .commitment = context {
            message = """
            Ask to rename this commitment, sharpen its description, or turn it off on Focus. \
            When your Sovereign applies a change, it updates here automatically.
            """
        } else if case .plan = context {
            message = """
            Continue this anytime — refine steps, ask questions, or decide what to do next. \
            When your Sovereign updates it, Focus stays in sync.
            """
        } else {
            message = "Messages here appear in the full chat stream too."
        }
        var subtitle = ""
        if connectionManager.routingMode == "phoenix" {
            subtitle = "Auto-select will choose a thinking service when you send a message."
        } else if let routed = connectionManager.lastRoutedDisplayName {
            subtitle = "Last routed to \(routed)."
        }
        return VStack(spacing: Spacing.sm) {
            EmptyState(
                icon: "bubble.left.and.bubble.right",
                title: "Chat about \(context.displayTitle)",
                message: message
            )
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
            }
        }
    }

    private func attachmentChips(_ attachments: [MessageAttachment]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(attachments) { attachment in
                if attachment.missing {
                    Text(attachment.filename)
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 4)
                        .background(ColorTheme.surfaceElevated())
                        .clipShape(Capsule())
                } else {
                    ShareLink(item: URL(fileURLWithPath: attachment.localPath)) {
                        Label(attachment.filename, systemImage: "paperclip")
                            .font(.caption)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 4)
                    .background(ColorTheme.surfaceElevated())
                    .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Input Bar

    private func toolApprovalCard(_ approval: PendingToolApproval) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Your Sovereign needs approval")
                .font(.subheadline.weight(.semibold))
            Text(approval.description)
                .font(.caption)
                .foregroundColor(ColorTheme.mutedText())
            if !approval.command.isEmpty {
                Text(approval.command)
                    .font(.caption.monospaced())
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ColorTheme.surfaceElevated())
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            HStack(spacing: Spacing.sm) {
                ForEach(["once", "session", "always", "deny"], id: \.self) { choice in
                    if approval.choices.contains(choice) {
                        Button(choice == "deny" ? "Deny" : choice.capitalized) {
                            Task {
                                try? await connectionManager.respondToToolApproval(choice: choice)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(choice == "deny" ? ColorTheme.error() : ColorTheme.accent())
                    }
                }
            }
        }
        .padding()
        .background(ColorTheme.surface())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: Spacing.sm) {
                Button {
                    Haptics.lightTap()
                    proposeFirst.toggle()
                } label: {
                    Image(systemName: proposeFirst ? "list.clipboard.fill" : "bubble.left.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(proposeFirst ? ColorTheme.accent() : ColorTheme.mutedText())
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!connectionManager.isChatComposerReady)
                .accessibilityLabel(proposeFirst ? "Propose first" : "Chat")
                .accessibilityHint("Switch between a spoken reply and a plan to review")

                TextField(
                    connectionManager.isHydratingAfterLink
                        ? "Loading mission data. Please wait…"
                        : selectedConversation != nil
                        ? (proposeFirst
                            ? "Ask for a plan about \(selectedConversation!.displayTitle)…"
                            : "Message about \(selectedConversation!.displayTitle)…")
                        : (proposeFirst
                            ? "Ask your Sovereign to propose a plan…"
                            : "Message your Sovereign…"),
                    text: $messageText,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .lineLimit(1...5)
                .focused($isFocused)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            dismissComposer()
                        }
                        .fontWeight(.semibold)
                        .accessibilityLabel("Close keyboard and show tabs")
                    }
                }
                .disabled(!connectionManager.isChatComposerReady)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(ColorTheme.chatInput())
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(isFocused ? ColorTheme.accent().opacity(0.4) : ColorTheme.border(), lineWidth: 1)
                )

                if isSending {
                    Button {
                        Haptics.lightTap()
                        connectionManager.cancelInFlightChat()
                        isSending = false
                        sendError = "Stopped. Send Hi again when Device link is green."
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(ColorTheme.warning())
                    }
                    .accessibilityLabel("Stop waiting")
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
                    .disabled(
                        connectionManager.isHydratingAfterLink
                            || messageText.trimmingCharacters(in: .whitespaces).isEmpty
                    )
                    .animation(Motion.light, value: messageText)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.xs)
            .padding(.bottom, 6)

            if isSending, connectionManager.streamingAssistantText.isEmpty {
                Text(connectionManager.turnActivityHint
                    ?? "Waiting on your Centurion. Tap stop if this hangs.")
                    .font(.caption2)
                    .foregroundColor(ColorTheme.mutedText())
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, 4)
            } else if sendError == nil,
                      connectionManager.isChatComposerReady,
                      connectionManager.llmHealth.needsAttention {
                Button {
                    showRecoverySheet = true
                } label: {
                    Text("Thinking needs attention — tap to check")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(ColorTheme.warning())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, 4)
            }
        }
        .background(ColorTheme.background())
    }

    // MARK: - Actions

    private static func looksLikePipeWait(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("too long")
            || lowered.contains("reconnecting")
            || lowered.contains("stopped")
            || lowered.contains("chat is still waiting")
            || lowered.contains("loading mission data")
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        guard connectionManager.isChatComposerReady else { return }

        sendError = nil
        lastFailedMessage = text
        Haptics.messageSent()
        messageText = ""
        isSending = true
        isFocused = false

        // Select the conversation before the async send so the user's message
        // stays visible while waiting for the Sovereign response.
        let stayOnAllChat = selectedConversation == nil
        let context: ConversationContext
        if let selected = selectedConversation {
            context = selected.context
        } else {
            context = ConversationContext.standalone(title: "Quick Chat")
            if !stayOnAllChat {
                selectedConversation = messageService.findOrCreateConversation(for: context)
            } else {
                _ = messageService.findOrCreateConversation(for: context)
            }
        }

        Task {
            do {
                let conversation = try await messageService.sendMessage(
                    text,
                    in: context,
                    missionStore: missionStore,
                    planStore: planStore,
                    proposeFirst: proposeFirst
                )
                if !stayOnAllChat {
                    selectedConversation = conversation
                }
                withAnimation(Motion.standard) {
                    showTray = false
                }
            } catch {
                Haptics.error()
                sendError = connectionManager.friendlyRemoteError(error)
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

    private func scrollToLastInStream(_ proxy: ScrollViewProxy) {
        if let last = messageService.allMessages.last {
            withAnimation(Motion.heavy) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Message Row

    private func streamingDraftRow(_ text: String) -> some View {
        HStack(alignment: .bottom, spacing: Spacing.xs) {
            ZStack {
                Circle()
                    .fill(ColorTheme.accent().opacity(0.15))
                    .frame(width: 28, height: 28)
                Circle()
                    .fill(ColorTheme.accent())
                    .frame(width: 8, height: 8)
            }
            .padding(.bottom, 4)

            Text(text)
                .font(.system(size: 17))
                .foregroundColor(ColorTheme.primaryText())
                .lineSpacing(5)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 10)
                .background(ColorTheme.mutedText().opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .textSelection(.enabled)

            Spacer(minLength: 48)
        }
        .accessibilityLabel("Streaming reply")
    }

    private func messageRow(_ message: Message, showContext: Bool) -> some View {
        let conversation = messageService.conversations.first(where: { $0.id == message.conversationId })
        let badge = conversation?.missionBadge

        if message.role == .system {
            return AnyView(
                Text(message.content)
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(ColorTheme.mutedText().opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            )
        }

        return AnyView(HStack(alignment: .bottom, spacing: Spacing.xs) {
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
            if showContext, let badge {
                Text(badge.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(badge.color)
                    .padding(.horizontal, 4)
                    .lineLimit(1)
            }

            Text(message.content)
                .font(.system(size: 17))
                .foregroundColor(ColorTheme.primaryText())
                .lineSpacing(5)
                .textSelection(.enabled)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 10)
                .background(message.role == .user
                    ? ColorTheme.accent().opacity(0.12)
                    : ColorTheme.surfaceElevated())
                .clipShape(BubbleShape(role: message.role))
                .overlay(
                    BubbleShape(role: message.role)
                        .stroke(ColorTheme.border(), lineWidth: message.role == .user ? 0 : 0.5)
                )
                .shadow(
                    color: Elevation.cardShadow(colorScheme: colorScheme).opacity(0.65),
                    radius: 4,
                    x: 0,
                    y: 2
                )

            if !message.attachments.isEmpty {
                attachmentChips(message.attachments)
            }
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
    })
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
