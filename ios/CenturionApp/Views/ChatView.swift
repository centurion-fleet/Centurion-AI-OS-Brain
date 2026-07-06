import SwiftUI

struct ChatView: View {
    let conversation: Conversation
    @EnvironmentObject private var messageService: MessageService
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var messageText = ""
    @State private var isSending = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollView in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Encryption banner
                        HStack {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                            Text("End-to-end encrypted")
                                .font(.caption)
                        }
                        .foregroundColor(.green)
                        .padding(.top, 8)
                        
                        ForEach(messageService.currentMessages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messageService.currentMessages.count) { _, _ in
                    if let last = messageService.currentMessages.last {
                        withAnimation {
                            scrollView.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input bar
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 12) {
                    TextField("Message your Centurion…", text: $messageText)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .disabled(connectionManager.connectionState != .connected || isSending)
                    
                    if isSending {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                        }
                        .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty
                                  || connectionManager.connectionState != .connected)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(.ultraThinMaterial)
        }
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            messageService.loadConversation(conversation.id)
            isFocused = true
        }
    }
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        
        messageText = ""
        isSending = true
        
        Task {
            do {
                try await messageService.sendMessage(text, to: conversation.id)
            } catch {
                print("Failed to send: \(error)")
            }
            isSending = false
        }
    }
}

struct MessageBubble: View {
    let message: Message
    
    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            if message.role == .centurion { /* Centurion avatar space */ }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .centurion {
                    Text("Centurion")
                        .font(.caption2)
                        .foregroundColor(message.role.tintColor)
                }
                
                Text(message.content)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(message.role == .user
                                ? message.role.tintColor.opacity(0.2)
                                : Color(.systemGray6))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            
            if message.role == .centurion { Spacer(minLength: 48) }
            if message.role == .user { /* User avatar space */ }
        }
    }
}
