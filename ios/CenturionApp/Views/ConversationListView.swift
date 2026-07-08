import SwiftUI

/// Conversation list — premium side panel with amber-accented rows.
/// Each row feels like a physical card with spring touch feedback.
struct ConversationListView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var messageService: MessageService
    
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
                    Button(action: {
                        Haptics.mediumTap()
                        onSelect?(conversation)
                    }) {
                        ConversationRowPremium(conversation: conversation)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Conversations")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if connectionManager.connectionState == .disconnected {
                connectionManager.startDiscovery()
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: connectionManager.connectionState == .connected
                  ? "message.fill"
                  : "antenna.radiowaves.left.and.right")
                .font(.system(size: 40))
                .foregroundColor(ColorTheme.mutedText())
            
            if connectionManager.connectionState == .connected {
                Text("No conversations yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(ColorTheme.primaryText())
                Text("Your first message will start a new conversation")
                    .font(.system(size: 15))
                    .foregroundColor(ColorTheme.mutedText())
                    .multilineTextAlignment(.center)
            } else if connectionManager.connectionState == .discovering {
                ProgressView()
                    .tint(ColorTheme.accent())
                Text("Looking for your Centurion…")
                    .font(.system(size: 15))
                    .foregroundColor(ColorTheme.mutedText())
            } else {
                Text("Not connected")
                    .font(.system(size: 17, weight: .semibold))
                Text("Go to Settings to connect")
                    .font(.system(size: 14))
                    .foregroundColor(ColorTheme.mutedText())
            }
        }
        .padding()
    }
}

// MARK: - Premium Conversation Row

struct ConversationRowPremium: View {
    let conversation: Conversation
    
    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Amber accent indicator
            ZStack {
                Circle()
                    .fill(ColorTheme.accent().opacity(0.10))
                    .frame(width: 44, height: 44)
                Image(systemName: "message.fill")
                    .font(.system(size: 16))
                    .foregroundColor(ColorTheme.accent())
            }
            
            // Content
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(conversation.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ColorTheme.primaryText())
                        .lineLimit(1)
                    
                    if conversation.isEncrypted {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8))
                            .foregroundColor(ColorTheme.success())
                    }
                    
                    Spacer()
                    
                    Text(conversation.lastActive, style: .relative)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(ColorTheme.mutedText())
                }
                
                Text(conversation.lastMessage)
                    .font(.system(size: 14))
                    .foregroundColor(ColorTheme.mutedText())
                    .lineLimit(1)
            }
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
    }
}
