import SwiftUI

/// Main application entry — five tabs.
///
/// The tab bar encodes the Remote Control theme:
/// - Connect tab — the pairing ceremony (was "Remote")
/// - Remote tab — the unified mission stream (was "Chat")
/// - Pulse tab — live AI activity, wins, decisions
/// - Security tab — encryption dashboard
/// - Settings tab — identity and configuration
struct ContentView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var messageService: MessageService
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Connect — pair and connect to your Centurion
            ConnectionView()
                .tabItem {
                    Label(
                        "Connect",
                        systemImage: connectionManager.connectionState == .connected
                            ? "app.connected.to.app.below.fill"
                            : "antenna.radiowaves.left.and.right"
                    )
                }
                .tag(0)

            // Remote — the conversation stream with your Centurion
            ChatView()
                .tabItem {
                    Label("Remote", systemImage: "message.fill")
                }
                .tag(1)

            // Pulse — live AI dashboard
            MissionPortfolioView()
                .tabItem {
                    Label("Pulse", systemImage: "waveform.path.ecg")
                }
                .tag(2)

            // Security — encryption and trust
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
