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
                .tabItem {
                    Label("Chat", systemImage: "message.fill")
                }
                .tag(0)

            MissionPortfolioView()
                .tabItem {
                    Label("Mission", systemImage: "target")
                }
                .tag(1)

            SecurityHubView()
                .tabItem {
                    Label("Security", systemImage: "shield.fill")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(ColorTheme.accent())
        .onAppear {
            // Seed sample data after view has appeared (avoids freeze from
            // rendering 15+ message rows during launch)
            DispatchQueue.main.async {
                messageService.seedInitialData()
            }
        }
    }

    // MARK: - Main Chat (unified stream + context filter)

    private var mainConversationsView: some View {
        NavigationStack {
            chatContent
                .navigationTitle(selectedConversation?.displayTitle ?? "All Chat")
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
