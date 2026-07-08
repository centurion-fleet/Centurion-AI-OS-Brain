import SwiftUI

/// Main application entry
struct ContentView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var messageService: MessageService
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatView(conversation: nil)
                .tabItem { Label("Chat", systemImage: "message.fill") }
                .tag(0)

            MissionPortfolioView()
                .tabItem { Label("Mission", systemImage: "target") }
                .tag(1)

            SecurityHubView()
                .tabItem { Label("Security", systemImage: "shield.fill") }
                .tag(2)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .tint(ColorTheme.accent())
        .onAppear {
            DispatchQueue.main.async {
                messageService.seedInitialData()
            }
        }
    }
}
