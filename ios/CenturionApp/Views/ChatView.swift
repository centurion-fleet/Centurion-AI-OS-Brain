import SwiftUI

/// Full chat view — physics-based message bubbles with spring animations.
/// Every message enters with weight and bounce, like real objects.
struct ChatView: View {
    let conversation: Conversation
    @EnvironmentObject private var messageService: MessageService
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var messageText = ""
    @State private var isSending = false
    @State private var lastMessageId: UUID?
    @FocusState private var isFocused: Bool
    
    let onSwitchConversation: ((Conversation) -> Void)?
    
    init(conversation: Conversation, onSwitchConversation: ((Conversation) -> Void)? = nil) {
        self.conversation = conversation
        self.onSwitchConversation = onSwitchConversation
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Spacing.sm) {
                        // Encryption banner
                        encryptionBanner
                        
                        ForEach(messageService.currentMessages) { message in
                            MessageBubblePhysics(message: message)
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.85, anchor: message.role == .user ? .bottomTrailing : .bottomLeading)
                                        .combined(with: .opacity)
                                        .animation(Motion.appear),
                                    removal: .opacity.animation(Motion.light)
                                ))
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messageService.currentMessages.count) { _, newCount in
                    if let last = messageService.currentMessages.last {
                        withAnimation(Motion.heavy) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    if let last = messageService.currentMessages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            
            // Input bar
            inputBar
        }
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            messageService.loadConversation(conversation.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFocused = true
            }
        }
    }
    
    // MARK: - Encryption Banner
    
    private var encryptionBanner: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .bold))
            Text("End-to-end encrypted")
                .font(.system(size: 11, weight: .medium, design: .default))
        }
        .foregroundColor(ColorTheme.success())
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxs + 2)
        .background(ColorTheme.success().opacity(0.08))
        .clipShape(Capsule())
        .padding(.top, Spacing.xs)
        .padding(.bottom, Spacing.xxs)
    }
    
    // MARK: - Input Bar
    
    private var inputBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(ColorTheme.border())
                .frame(height: 0.5)
            
            HStack(spacing: Spacing.sm) {
                // Text field with amber accent
                HStack(spacing: 0) {
                    TextField("Message your Centurion…", text: $messageText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .focused($isFocused)
                        .disabled(connectionManager.connectionState != .connected || isSending)
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
                
                // Send button
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
                                || connectionManager.connectionState != .connected
                                ? ColorTheme.mutedText()
                                : ColorTheme.accent()
                            )
                    }
                    .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty
                              || connectionManager.connectionState != .connected)
                    .scaleEffect(messageText.trimmingCharacters(in: .whitespaces).isEmpty ? 1.0 : 1.0)
                    .animation(Motion.light, value: messageText)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(.ultraThinMaterial)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 4)
        }
    }
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        
        Haptics.messageSent()
        messageText = ""
        isSending = true
        
        Task {
            do {
                try await messageService.sendMessage(text, to: conversation.id)
            } catch {
                Haptics.error()
                print("Failed to send: \(error)")
            }
            isSending = false
        }
    }
}

// MARK: - Physics Message Bubble

/// A message bubble with spring-physics animation on appearance.
/// Enters with weight, bounce, and purpose.
struct MessageBubblePhysics: View {
    let message: Message
    @State private var isAppeared = false
    
    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.xs) {
            if message.role == .user { Spacer(minLength: 48) }
            
            if message.role == .centurion {
                // Centurion avatar — small amber sphere
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
            
            // Bubble content
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
            .onAppear {
                withAnimation(Motion.appear) {
                    isAppeared = true
                }
            }
            
            if message.role == .centurion { Spacer(minLength: 48) }
            
            if message.role == .user {
                // User avatar — small amber sphere
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

/// Custom chat bubble shape with tailored corners per role.
struct BubbleShape: Shape {
    let role: MessageRole
    
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        var path = Path()
        
        switch role {
        case .user:
            // User bubble — square bottom-right
            path = Path(roundedRect: rect,
                       cornerSize: CGSize(width: radius, height: radius),
                       style: .continuous)
            // Flatten bottom-right
            path.addRect(CGRect(x: rect.maxX - radius, y: rect.maxY - radius,
                               width: radius, height: radius))
        case .centurion:
            // Centurion bubble — square bottom-left
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
