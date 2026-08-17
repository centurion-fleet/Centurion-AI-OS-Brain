import SwiftUI
import UIKit

/// Main application entry — four tabs: Chat, Focus, Collab, You.
/// Only the selected tab is built (lazy) so launch stays fast.
struct ContentView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var messageService: MessageService
    @EnvironmentObject private var dataMode: AppDataMode
    @EnvironmentObject private var planStore: PlanStore
    @EnvironmentObject private var swarmStore: SwarmStore
    @EnvironmentObject private var missionStore: MissionStore
    @State private var selectedTab = 0
    @State private var loadedTabs: Set<Int> = [0]
    @AppStorage("collab_last_seen") private var lastSeenCollab: TimeInterval = 0

    /// Badge only for real recovery — not for first-run “not linked yet”.
    private var showYouAttentionBadge: Bool {
        if connectionManager.isCryptoChatReady {
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

    /// Outstanding Decisions needed. Swarm waiting is Collab.
    private var homeAttentionCount: Int {
        PulseBadgeCounts.outstandingFocus(planStore: planStore, missionStore: missionStore)
    }

    /// Collaborations the user has not opened since they last changed.
    private var collabAttentionCount: Int {
        PulseBadgeCounts.unseenCollab(swarmStore: swarmStore, lastSeen: lastSeenCollab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DeferredTabContent(tag: AdrianNavigation.chatTab, selection: $selectedTab, loadedTabs: $loadedTabs) {
                ChatView()
            }
            .tabItem {
                Label("Chat", systemImage: "message.fill")
            }
            .tag(AdrianNavigation.chatTab)

            DeferredTabContent(tag: AdrianNavigation.focusTab, selection: $selectedTab, loadedTabs: $loadedTabs) {
                MissionPortfolioView()
            }
            .tabItem {
                Label("Focus", systemImage: "waveform.path.ecg")
            }
            .badge(homeAttentionCount)
            .tag(AdrianNavigation.focusTab)

            DeferredTabContent(tag: AdrianNavigation.collabTab, selection: $selectedTab, loadedTabs: $loadedTabs) {
                CollabTabView()
            }
            .tabItem {
                Label("Collab", systemImage: "circle.hexagongrid.fill")
            }
            .badge(collabAttentionCount)
            .tag(AdrianNavigation.collabTab)

            DeferredTabContent(tag: AdrianNavigation.youTab, selection: $selectedTab, loadedTabs: $loadedTabs) {
                SettingsView()
            }
            .tabItem {
                Label("You", systemImage: "person.crop.circle")
            }
            .badge(showYouAttentionBadge ? "!" : nil)
            .tag(AdrianNavigation.youTab)
        }
        .tint(ColorTheme.accent())
        .onAppear {
            // Bronze attention chip — not the system red error badge.
            UITabBarItem.appearance().badgeColor = UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.827, green: 0.804, blue: 0.749, alpha: 1.0)
                    : UIColor(red: 0.263, green: 0.220, blue: 0.188, alpha: 1.0)
            }
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == AdrianNavigation.collabTab {
                lastSeenCollab = Date.timeIntervalSinceReferenceDate
            }
        }
        .onChange(of: swarmStore.heroSwarms) { _, _ in
            if selectedTab == AdrianNavigation.collabTab {
                lastSeenCollab = Date.timeIntervalSinceReferenceDate
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .centurionSelectTab)) { notification in
            if let tab = notification.object as? Int {
                selectedTab = min(max(tab, 0), AdrianNavigation.youTab)
            }
        }
        #if DEBUG
        .task(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(400))
            await MainActor.run {
                if dataMode.showsDemoContent {
                    messageService.seedInitialData()
                    planStore.seedPreviewIfNeeded(showsDemoContent: true)
                }
            }
        }
        #endif
    }
}
