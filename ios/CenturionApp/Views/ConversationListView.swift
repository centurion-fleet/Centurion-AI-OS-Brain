import SwiftUI

/// Conversation list — used both as the main inbox and as a GROK-style
/// side panel sheet accessible via the ☰ hamburger button.
struct ConversationListView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var messageService: MessageService
    
    /// Called when a conversation is selected from the list
    let onSelect: ((Conversation) -> Void)?
    
    init(onSelect: ((Conversation) -> Void)? = nil) {
        self.onSelect = onSelect
    }
    
    var body: some View {
        Group {
            if messageService.conversations.isEmpty {
                emptyState
            } else {
                List(messageService.conversations) { conversation in
                    Button(action: { onSelect?(conversation) }) {
                        ConversationRow(conversation: conversation)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            if connectionManager.connectionState == .disconnected {
                connectionManager.startDiscovery()
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: connectionManager.connectionState == .connected
                  ? "message.fill"
                  : "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            if connectionManager.connectionState == .connected {
                Text("No conversations yet")
                    .font(.headline)
                Text("Your first message will start a new conversation")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if connectionManager.connectionState == .discovering {
                ProgressView()
                Text("Looking for your Centurion…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("Not connected")
                    .font(.headline)
                Text("Go to the Settings tab to connect")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

/// A single row in the conversation list
struct ConversationRow: View {
    let conversation: Conversation
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if conversation.isEncrypted {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
                Text(conversation.lastActive, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(conversation.lastMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}
