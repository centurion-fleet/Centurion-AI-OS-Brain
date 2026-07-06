import SwiftUI

struct ConversationListView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var messageService: MessageService
    @State private var showNewChat = false
    
    var body: some View {
        NavigationStack {
            Group {
                if messageService.conversations.isEmpty {
                    emptyState
                } else {
                    List(messageService.conversations) { conversation in
                        NavigationLink {
                            ChatView(conversation: conversation)
                        } label: {
                            ConversationRow(conversation: conversation)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Centurion")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showNewChat = true }) {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(connectionManager.connectionState != .connected)
                }
            }
            .onAppear {
                if connectionManager.connectionState == .disconnected {
                    connectionManager.startDiscovery()
                }
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
                Text("Connected to your Centurion")
                    .font(.headline)
                Text("Tap + to start a conversation")
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
                Text("Go to the Connect tab to find your Centurion")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

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
