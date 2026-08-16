import SwiftUI

/// Main application entry — three tabs: Chat, Focus, You.
/// Only the selected tab is built (lazy) so launch stays fast.
struct ContentView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var messageService: MessageService
    @EnvironmentObject private var dataMode: AppDataMode
    @EnvironmentObject private var planStore: PlanStore
    @EnvironmentObject private var swarmStore: SwarmStore
    @State private var selectedTab = 0
    @State private var loadedTabs: Set<Int> = [0]

    // Same last-seen keys as Focus subsection pills — clearing a pill updates the tab badge.
    @AppStorage("pulse_note_plans") private var lastSeenPlans: TimeInterval = 0
    @AppStorage("pulse_note_wins") private var lastSeenWins: TimeInterval = 0
    @AppStorage("pulse_note_outputs") private var lastSeenOutputs: TimeInterval = 0
    @AppStorage("pulse_note_decisions") private var lastSeenDecisions: TimeInterval = 0
    @AppStorage("pulse_note_pulse") private var lastSeenThoughts: TimeInterval = 0

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

    /// Sum of Home subsection “new” counts for the tab bar badge.
    private var homeAttentionCount: Int {
        PulseBadgeCounts.total(
            isCryptoChatReady: connectionManager.isCryptoChatReady,
            showsDemoContent: dataMode.showsDemoContent,
            swarmStore: swarmStore,
            planStore: planStore,
            lastSeen: .init(
                plans: lastSeenPlans,
                wins: lastSeenWins,
                outputs: lastSeenOutputs,
                decisions: lastSeenDecisions,
                thoughts: lastSeenThoughts
            )
        )
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
                Label("Focus", systemImage: "waveform.path.ecg")
            }
            .badge(homeAttentionCount)
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
                selectedTab = min(max(tab, 0), 2)
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
