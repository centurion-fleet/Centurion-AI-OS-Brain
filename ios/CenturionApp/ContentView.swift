import SwiftUI

/// Main application entry — GROK-style with hamburger conversations
/// and a premium custom tab bar.
struct ContentView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var messageService: MessageService
    @State private var selectedTab = 0
    @State private var showConversations = false
    @State private var selectedConversation: Conversation?
    @State private var showContextChat = false
    @State private var contextChatMessage = ""
    
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
        // Floating chat FAB — appears on all tabs
        .overlay(alignment: .bottomTrailing) {
            contextChatButton
        }
        .sheet(isPresented: $showContextChat) {
            contextChatSheet
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
    
    // MARK: - Context Chat FAB
    
    private var contextChatButton: some View {
        Button(action: {
            Haptics.mediumTap()
            contextChatMessage = ""
            withAnimation(Motion.heavy) {
                showContextChat = true
            }
        }) {
            Image(systemName: "message.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(ColorTheme.accent())
                .clipShape(Circle())
                .shadow(color: ColorTheme.accent().opacity(0.3), radius: 8, y: 4)
        }
        .padding(.trailing, Spacing.md)
        .padding(.bottom, 80) // Above tab bar
        .transition(.scale.combined(with: .opacity))
    }
    
    /// Context-aware chat sheet — knows which tab the user was on
    private var contextChatSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Context header — shows what the user was looking at
                contextHeader
                
                Divider()
                
                // Message input
                VStack(spacing: Spacing.md) {
                    ScrollView {
                        Text("Share your thoughts with your Centurion. It will know you were looking at \(currentTabContext).")
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.mutedText())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Spacing.md)
                    }
                    
                    HStack(spacing: Spacing.sm) {
                        TextField("Share your thoughts…", text: $contextChatMessage)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(ColorTheme.chatInput())
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(ColorTheme.border(), lineWidth: 1)
                            )
                        
                        Button(action: sendContextMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(
                                    contextChatMessage.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? ColorTheme.mutedText() : ColorTheme.accent()
                                )
                        }
                        .disabled(contextChatMessage.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.bottom, Spacing.md)
                }
                .padding(.horizontal, Spacing.md)
            }
            .navigationTitle("Tell your Centurion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showContextChat = false }
                }
            }
        }
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
    }
    
    private var contextHeader: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: tabContextIcon)
                .font(.caption)
                .foregroundColor(ColorTheme.accent())
            Text(currentTabContext)
                .font(.caption)
                .foregroundColor(ColorTheme.accent())
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(ColorTheme.accent().opacity(0.05))
    }
    
    private var currentTabContext: String {
        switch selectedTab {
        case 0: return "Conversations"
        case 1: return "Mission Control"
        case 2: return "Security"
        case 3: return "Settings"
        default: return "the app"
        }
    }
    
    private var tabContextIcon: String {
        switch selectedTab {
        case 0: return "message.fill"
        case 1: return "target"
        case 2: return "shield.fill"
        case 3: return "gearshape.fill"
        default: return "app.fill"
        }
    }
    
    private func sendContextMessage() {
        let message = contextChatMessage.trimmingCharacters(in: .whitespaces)
        guard !message.isEmpty else { return }
        
        Haptics.messageSent()
        // In production: send to Centurion with context
        // [User was viewing: $currentTabContext]
        // User says: $message
        
        contextChatMessage = ""
        showContextChat = false
    }
    
    private func selectDefaultConversation() {
        if let first = messageService.conversations.first {
            selectedConversation = first
        }
    }
}
