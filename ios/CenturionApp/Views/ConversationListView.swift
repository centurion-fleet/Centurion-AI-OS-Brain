import SwiftUI

/// Conversation list — organized by mission area groupings.
///
/// - **Active Missions** — programs, targets, tasks with recent chat activity
/// - **Standalone Chats** — direct messages not tied to a mission element
///
/// Each row shows the mission context path, last message preview, and timestamp.
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
                let missionConvs = messageService.conversations.filter { !$0.context.isStandalone }
                let standaloneConvs = messageService.conversations.filter { $0.context.isStandalone }
                List {
                    // Mission context conversations
                    if !missionConvs.isEmpty {
                        Section {
                            ForEach(missionConvs) { conversation in
                                conversationRow(conversation)
                            }
                        } header: {
                            missionSectionHeader
                        }
                    }

                    // Standalone conversations
                    if !standaloneConvs.isEmpty {
                        Section {
                            ForEach(standaloneConvs) { conversation in
                                conversationRow(conversation)
                            }
                        } header: {
                            standaloneSectionHeader
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
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

    // MARK: - Section Headers

    private var missionSectionHeader: some View {
        CenturionSectionHeader(title: "Active Missions", icon: "target")
            .padding(.top, Spacing.xs)
    }

    private var standaloneSectionHeader: some View {
        CenturionSectionHeader(title: "Chats", icon: "message.fill")
            .padding(.top, Spacing.xs)
    }

    // MARK: - Conversation Row

    private func conversationRow(_ conversation: Conversation) -> some View {
        Button(action: {
            Haptics.mediumTap()
            onSelect?(conversation)
        }) {
            HStack(spacing: Spacing.sm) {
                // Icon — mission-level icon or chat icon
                ZStack {
                    Circle()
                        .fill(conversation.missionBadge.color.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: conversation.icon)
                        .font(.system(size: 14))
                        .foregroundColor(conversation.missionBadge.color)
                }

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(conversation.displayTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(ColorTheme.primaryText())
                            .lineLimit(1)

                        Spacer()

                        Text(conversation.lastActive, style: .relative)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundColor(ColorTheme.mutedText())
                    }

                    // Context path (e.g. "Q3 Go-to-Market > Partner Onboarding")
                    if !conversation.context.isStandalone {
                        Text(conversation.contextPath)
                            .font(.system(size: 11))
                            .foregroundColor(conversation.missionBadge.color.opacity(0.7))
                            .lineLimit(1)
                    }

                    // Last message preview
                    if let lastMessage = messageService.messages(for: conversation.id).last {
                        Text(lastMessage.content)
                            .font(.system(size: 13))
                            .foregroundColor(ColorTheme.mutedText())
                            .lineLimit(1)
                            .padding(.top, 1)
                    }
                }
            }
            .padding(.vertical, Spacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Group {
            if connectionManager.connectionState == .connected {
                EmptyState(
                    icon: "message.fill",
                    title: "No conversations yet",
                    message: "Chat about a mission target or send a message — conversations appear here automatically."
                )
            } else if connectionManager.connectionState == .discovering {
                LoadingState(message: "Looking for your Centurion…")
            } else {
                EmptyState(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Not connected",
                    message: "Open You to link your iPhone to your Centurion."
                )
            }
        }
        .padding()
    }
}
