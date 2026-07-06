import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Chat
            ConversationListView()
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
    }
}
