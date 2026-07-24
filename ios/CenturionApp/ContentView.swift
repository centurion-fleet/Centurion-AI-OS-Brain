import SwiftUI

/// Main application entry — three tabs: Chat, Home, You.
/// Only the selected tab is built (lazy) so launch stays fast.
struct ContentView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var messageService: MessageService
    @EnvironmentObject private var dataMode: AppDataMode
    @EnvironmentObject private var planStore: PlanStore
    @State private var selectedTab = 0
    @State private var loadedTabs: Set<Int> = [0]

    /// Badge only for real recovery — not for first-run “not linked yet”.
    private var showYouAttentionBadge: Bool {
        if connectionManager.connectionState == .connected {
            return connectionManager.llmHealth.needsAttention
        }
        if case .error = connectionManager.connectionState {
            return true
        }
        // Had a prior link / saved pairing but is offline now.
        if connectionManager.connectedDevice != nil {
            return true
        }
        return false
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DeferredTabContent(tag: 0, selection: $selectedTab, loadedTabs: $loadedTabs) {
                ChatView()
            }
            .tabItem {
                Label("Chat", systemImage: "message.fill")
            }
            .tag(0)

            DeferredTabContent(tag: 1, selection: $selectedTab, loadedTabs: $loadedTabs) {
                MissionPortfolioView()
            }
            .tabItem {
                Label("Home", systemImage: "waveform.path.ecg")
            }
            .tag(1)

            DeferredTabContent(tag: 2, selection: $selectedTab, loadedTabs: $loadedTabs) {
                SettingsView()
            }
            .tabItem {
                Label("You", systemImage: "person.crop.circle")
            }
            .badge(showYouAttentionBadge ? "!" : nil)
            .tag(2)
        }
        .tint(ColorTheme.accent())
        .onReceive(NotificationCenter.default.publisher(for: .centurionSelectTab)) { notification in
            if let tab = notification.object as? Int {
                selectedTab = remapLegacyTab(tab)
            }
        }
        .task(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(400))
            await MainActor.run {
                if dataMode.showsDemoContent {
                    messageService.seedInitialData()
                    planStore.seedPreviewIfNeeded(showsDemoContent: true)
                }
            }
        }
    }

    /// Maps pre-3-tab indices: Connect(0)→You(2), Chat(1)→0, Home(2)→1, You(3)→2.
    private func remapLegacyTab(_ tab: Int) -> Int {
        switch tab {
        case 0: return 2
        case 1: return 0
        case 2: return 1
        case 3: return 2
        default: return min(max(tab, 0), 2)
        }
    }
}
