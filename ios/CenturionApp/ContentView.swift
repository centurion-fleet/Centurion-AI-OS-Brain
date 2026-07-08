import SwiftUI

/// Main application entry — GROK-style with hamburger conversations
/// and a premium custom tab bar.
///
/// The Chat tab shows the **full chronological stream** of ALL messages
/// from every mission context. Conversations are organized by mission area.
struct ContentView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var messageService: MessageService
    @State private var selectedTab = 0
    @State private var showConversations = false
    @State private var selectedConversation: Conversation?

    var body: some View {
        TabView(selection: $selectedTab) {
            mainConversationsView
                .tag(0)

            MissionPortfolioView()
                .tag(1)

            SecurityHubView()
                .tag(2)

            SettingsView()
                .tag(3)
        }
        .safeAreaInset(edge: .bottom) {
            customTabBar
        }
        .onAppear {
            if selectedConversation == nil {
                selectDefaultConversation()
            }
        }
    }

    // MARK: - Custom Tab Bar (flat — award-winning minimal style)

    private var customTabBar: some View {
        HStack(spacing: 0) {
            tabBarItem(index: 0, icon: "message.fill", label: "Chat")
            tabBarItem(index: 1, icon: "target", label: "Mission")
            tabBarItem(index: 2, icon: "shield.fill", label: "Security")
            tabBarItem(index: 3, icon: "gearshape.fill", label: "Settings")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.xxs + 4)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ColorTheme.border())
                .frame(height: 0.5)
        }
    }

    private func tabBarItem(index: Int, icon: String, label: String) -> some View {
        let isSelected = selectedTab == index
        return Button(action: {
            Haptics.lightTap()
            withAnimation(Motion.light) {
                selectedTab = index
            }
        }) {
            VStack(spacing: 4) {
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(ColorTheme.accent().opacity(0.15))
                            .frame(width: 44, height: 32)
                    }
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? ColorTheme.accent() : ColorTheme.mutedText())
                }

                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? ColorTheme.accent() : ColorTheme.mutedText())
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Main Chat (unified stream + context filter)

    private var mainConversationsView: some View {
        NavigationStack {
            chatContent
                .navigationTitle(selectedConversation?.displayTitle ?? "Mission Chat")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: Spacing.xs) {
                        Button(action: {
                            Haptics.mediumTap()
                            showConversations.toggle()
                        }) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(ColorTheme.accent())
                        }

                        // Show context icon when a mission conversation is selected
                        if let conv = selectedConversation, !conv.context.isStandalone {
                            Image(systemName: conv.icon)
                                .font(.system(size: 10))
                                .foregroundColor(conv.missionBadge.color)
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: Spacing.sm) {
                        if selectedConversation != nil {
                            Button(action: {
                                Haptics.lightTap()
                                withAnimation(Motion.light) {
                                    selectedConversation = nil
                                }
                            }) {
                                Image(systemName: "text.alignleft")
                                    .font(.system(size: 14))
                                    .foregroundColor(ColorTheme.dimAccent())
                            }
                        }

                        if connectionManager.connectionState == .connected {
                            StatusDot(isConnected: true)
                        }
                    }
                }
            }
            .sheet(isPresented: $showConversations) {
                conversationListSheet
            }
        }
    }

    private var conversationListSheet: some View {
        NavigationStack {
            ConversationListView { conversation in
                Haptics.mediumTap()
                selectedConversation = conversation
                showConversations = false
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Haptics.lightTap()
                        showConversations = false
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    /// The chat view content — either stream mode or context mode.
    /// Extracted to a computed property to avoid Swift type-checker issues
    /// with conditional ChatView trailing closures.
    @ViewBuilder
    private var chatContent: some View {
        if let conversation = selectedConversation {
            ChatView(conversation: conversation) { selected in
                selectedConversation = selected
                showConversations = false
            }
        } else {
            ChatView(conversation: nil) { selected in
                selectedConversation = selected
                showConversations = false
            }
        }
    }

    private func selectDefaultConversation() {
        if let first = messageService.conversations.first {
            selectedConversation = first
        }
    }
}
