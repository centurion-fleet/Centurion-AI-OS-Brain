import SwiftUI

/// Main application entry — shows conversation list as a slide-over panel
/// accessible via a hamburger button, GROK-style.
struct ContentView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var messageService: MessageService
    @State private var selectedTab = 0
    @State private var showConversations = false
    @State private var selectedConversation: Conversation?
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Conversations (main screen — hamburger ☰ to open list)
            mainConversationsView
                .tabItem {
                    Label("Chat", systemImage: "message.fill")
                }
                .tag(0)
            
            // Mission Control
            MissionPortfolioView()
                .tabItem {
                    Label("Mission", systemImage: "target")
                }
                .tag(1)
            
            // Security Hub
            SecurityHubView()
                .tabItem {
                    Label("Security", systemImage: connectionManager.connectionState == .connected
                          ? "lock.shield.fill" : "shield")
                }
                .tag(2)
            
            // Settings
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(Color(red: 1.0, green: 0.84, blue: 0.0)) // Centurion gold
        .onAppear {
            // Load or create default conversation
            if selectedConversation == nil {
                selectDefaultConversation()
            }
        }
    }
    
    /// The main chat screen with hamburger access to conversation list
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showConversations.toggle() }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.title3)
                            .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.0))
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    if connectionManager.connectionState == .connected {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
            }
            .sheet(isPresented: $showConversations) {
                conversationListSheet
            }
        }
    }
    
    /// Conversation list presented as a sheet (GROK-style side panel)
    private var conversationListSheet: some View {
        NavigationStack {
            ConversationListView { conversation in
                selectedConversation = conversation
                showConversations = false
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showConversations = false }
                }
            }
        }
    }
    
    /// Empty state when no conversation is selected
    private var emptyConversationState: some View {
        VStack(spacing: 16) {
            Image(systemName: "message.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No conversation selected")
                .font(.headline)
            
            Text("Tap ☰ to choose a conversation")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button("Browse Conversations") {
                showConversations = true
            }
            .buttonStyle(.bordered)
            .tint(Color(red: 1.0, green: 0.84, blue: 0.0))
        }
        .padding()
    }
    
    /// Select the most recent conversation or create one
    private func selectDefaultConversation() {
        if let first = messageService.conversations.first {
            selectedConversation = first
        }
    }
}
