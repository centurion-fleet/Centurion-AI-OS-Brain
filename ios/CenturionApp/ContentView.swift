import SwiftUI

/// Main application entry — five tabs.
/// Only the selected tab is built (lazy) so launch stays fast.
struct ContentView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var messageService: MessageService
    @EnvironmentObject private var dataMode: AppDataMode
    @State private var selectedTab = 0
    @State private var loadedTabs: Set<Int> = [0]

    private var showThinkingAttentionBadge: Bool {
        connectionManager.connectionState == .connected && connectionManager.llmHealth.needsAttention
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DeferredTabContent(tag: 0, selection: $selectedTab, loadedTabs: $loadedTabs) {
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
            .badge(showThinkingAttentionBadge ? "!" : nil)
            .tag(0)

            DeferredTabContent(tag: 1, selection: $selectedTab, loadedTabs: $loadedTabs) {
                ChatView()
            }
            .tabItem {
                Label("Chat", systemImage: "message.fill")
            }
            .tag(1)

            DeferredTabContent(tag: 2, selection: $selectedTab, loadedTabs: $loadedTabs) {
                MissionPortfolioView()
            }
            .tabItem {
                Label("Home", systemImage: "waveform.path.ecg")
            }
            .tag(2)

            DeferredTabContent(tag: 3, selection: $selectedTab, loadedTabs: $loadedTabs) {
                SecurityHubView()
            }
            .tabItem {
                Label(
                    "Privacy",
                    systemImage: connectionManager.connectionState == .connected
                        ? "lock.shield.fill"
                        : "shield"
                )
            }
            .tag(3)

            DeferredTabContent(tag: 4, selection: $selectedTab, loadedTabs: $loadedTabs) {
                SettingsView()
            }
            .tabItem {
                Label("You", systemImage: "gearshape.fill")
            }
            .tag(4)
        }
        .tint(ColorTheme.accent())
        .onReceive(NotificationCenter.default.publisher(for: .centurionSelectTab)) { notification in
            if let tab = notification.object as? Int {
                selectedTab = tab
            }
        }
        .task(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(400))
            await MainActor.run {
                if dataMode.showsDemoContent {
                    messageService.seedInitialData()
                }
            }
        }
    }
}
