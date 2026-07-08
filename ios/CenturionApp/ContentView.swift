import SwiftUI

/// Main application entry — GROK-style with hamburger conversations
/// and a premium custom tab bar.
struct ContentView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var messageService: MessageService
    @State private var selectedTab = 0
    @State private var showConversations = false
    @State private var selectedConversation: Conversation?
    
    private let accentGold = Color(red: 1.0, green: 0.84, blue: 0.0)
    
    var body: some View {
        // Main content area with safe area inset for the custom tab bar
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
    
    // MARK: - Main Conversations
    
    private var mainConversationsView: some View {
        NavigationStack {
            Group {
                if let conversation = selectedConversation {
                    ChatView(conversation: conversation) { selected in
                        selectedConversation = selected
                        showConversations = false
                    }
                } else {
                    emptyConversationState
                }
            }
            .navigationTitle(selectedConversation?.title ?? "Centurion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        Haptics.mediumTap()
                        showConversations.toggle()
                    }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(ColorTheme.accent())
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    if connectionManager.connectionState == .connected {
                        StatusDot(isConnected: true)
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
    
    private var emptyConversationState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "message.fill")
                .font(.system(size: 48))
                .foregroundColor(ColorTheme.mutedText())
            
            Text("No conversation selected")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(ColorTheme.primaryText())
            
            Text("Tap ☰ to choose a conversation")
                .font(.system(size: 15))
                .foregroundColor(ColorTheme.mutedText())
            
            Button("Browse Conversations") {
                Haptics.mediumTap()
                showConversations = true
            }
            .buttonStyle(AmberButtonStyle())
            .padding(.top, Spacing.xs)
        }
        .padding()
    }
    
    private func selectDefaultConversation() {
        if let first = messageService.conversations.first {
            selectedConversation = first
        }
    }
}
