import SwiftUI

/// Main application entry — four tabs.
///
/// The tab bar encodes the Remote Control theme:
/// - Remote tab (antenna / connected icon) — the pairing ceremony
/// - Chat tab — the mission stream
/// - Security tab — encryption dashboard
/// - Settings tab — identity and configuration
struct ContentView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var messageService: MessageService
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Remote Control — pair and connect
            ConnectionView()
                .tabItem {
                    Label(
                        "Remote",
                        systemImage: connectionManager.connectionState == .connected
                            ? "app.connected.to.app.below.fill"
                            : "antenna.radiowaves.left.and.right"
                    )
                }
                .tag(0)

            // Chat — the unified mission stream
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "message.fill")
                }
                .tag(1)

            // Mission Control — programs, targets, tasks
            MissionPortfolioView()
                .tabItem {
                    Label("Mission", systemImage: "target")
                }
                .tag(2)

            // Security Hub — encryption and trust
            SecurityHubView()
                .tabItem {
                    Label("Security", systemImage: connectionManager.connectionState == .connected
                          ? "lock.shield.fill" : "shield")
                }
                .tag(3)

            // Settings — identity, appearance, about
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .tint(ColorTheme.accent())
        .onAppear {
            DispatchQueue.main.async {
                messageService.seedInitialData()
            }
        }
    }
}
