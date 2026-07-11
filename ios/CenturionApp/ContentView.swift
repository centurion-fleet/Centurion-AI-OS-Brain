import SwiftUI

/// Main application entry — five tabs.
/// Only the selected tab is built (lazy) so launch stays fast.
struct ContentView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var messageService: MessageService
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DeferredTabContent(tag: 0, selection: $selectedTab) {
                ConnectionView()
            }
            .tabItem {
                Label(
                    "Connect",
                    systemImage: connectionManager.connectionState == .connected
                        ? "app.connected.to.app.below.fill"
                        : "antenna.radiowaves.left.and.right"
                )
            }
            .tag(0)

            DeferredTabContent(tag: 1, selection: $selectedTab) {
                ChatView()
            }
            .tabItem {
                Label("Remote", systemImage: "message.fill")
            }
            .tag(1)

            DeferredTabContent(tag: 2, selection: $selectedTab) {
                MissionPortfolioView()
            }
            .tabItem {
                Label("Pulse", systemImage: "waveform.path.ecg")
            }
            .tag(2)

            DeferredTabContent(tag: 3, selection: $selectedTab) {
                SecurityHubView()
            }
            .tabItem {
                Label(
                    "Security",
                    systemImage: connectionManager.connectionState == .connected
                        ? "lock.shield.fill"
                        : "shield"
                )
            }
            .tag(3)

            DeferredTabContent(tag: 4, selection: $selectedTab) {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(4)
        }
        .tint(ColorTheme.accent())
        .task(priority: .utility) {
            // Seed demo messages after first paint — never block launch.
            try? await Task.sleep(for: .milliseconds(400))
            await MainActor.run {
                messageService.seedInitialData()
            }
        }
    }
}
