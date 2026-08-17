import SwiftUI

@main
struct CenturionApp: App {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("centurion.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOnboarding: Bool
    @State private var services = AppServices()
    @State private var clearedDemoForConnection = false
    @State private var didAttemptAutoReconnect = false

    init() {
        // Skip the old in-app splash — system launch screen is enough.
        _showOnboarding = State(initialValue: !UserDefaults.standard.bool(forKey: "centurion.hasCompletedOnboarding"))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ColorTheme.background()
                    .ignoresSafeArea()

                ContentView()
                    .environmentObject(services.connectionManager)
                    .environmentObject(services.messageService)
                    .environmentObject(services.missionStore)
                    .environmentObject(services.adrianService)
                    .environmentObject(services.dataMode)
                    .environmentObject(services.swarmStore)
                    .environmentObject(services.planStore)
                    .environmentObject(services.beneficiaryStore)
                    .environmentObject(services.oversightStore)
                    .environmentObject(services.memoryHorizonStore)
                    .opacity(showOnboarding ? 0 : 1)
                    .allowsHitTesting(!showOnboarding)

                if showOnboarding {
                    WelcomeOnboardingView {
                        withAnimation(.easeOut(duration: 0.25)) {
                            showOnboarding = false
                        }
                        attemptAutoReconnectIfNeeded()
                    }
                    .environmentObject(services.connectionManager)
                    .environmentObject(services.missionStore)
                    .transition(.opacity)
                }
            }
            .preferredColorScheme(appearanceMode.colorScheme)
            .onAppear {
                attemptAutoReconnectIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    attemptAutoReconnectIfNeeded(force: true)
                    prefetchWhenLinked()
                }
            }
            .onReceive(services.connectionManager.$connectionState) { _ in
                syncLinkedState()
            }
            .onReceive(services.connectionManager.$transportPreference) { _ in
                syncLinkedState()
            }
            .onReceive(services.connectionManager.relayAway.$isConnected) { _ in
                syncLinkedState()
            }
        }
    }

    private func syncLinkedState() {
        let ready = services.connectionManager.isCryptoChatReady
        services.dataMode.update(isCryptoChatReady: ready)
        if ready {
            if !clearedDemoForConnection {
                services.messageService.clearDemoData()
                services.planStore.clearDemoData()
                ConversationStore.shared.restore(into: services.messageService)
                clearedDemoForConnection = true
            }
            prefetchWhenLinked()
        } else {
            clearedDemoForConnection = false
        }
    }

    /// After pairing, load missions on the Crypto Chat line before the composer unlocks.
    private func prefetchWhenLinked() {
        let connectionManager = services.connectionManager
        guard connectionManager.isCryptoChatReady else { return }
        if !connectionManager.isHydratingAfterLink, !connectionManager.didHydrateAfterLink {
            connectionManager.beginPostLinkHydration()
        }
        guard let generation = connectionManager.claimHydrationFetch() else { return }
        Task { @MainActor in
            await services.missionStore.refreshLifeStack(from: connectionManager)
            if connectionManager.linkHydrationGeneration == generation,
               connectionManager.isCryptoChatReady {
                await services.planStore.refreshFromHost(connectionManager: connectionManager)
            }
            connectionManager.endPostLinkHydration(generation: generation)
            // Missions unlock Chat. Finished / Documents / Needs your choice / Updates
            // use the same pipe next — they are slower, not missing.
            if connectionManager.linkHydrationGeneration == generation,
               connectionManager.isCryptoChatReady,
               !connectionManager.isRemoteTurnInFlight {
                await services.swarmStore.refresh(from: connectionManager)
            }
        }
    }

    private func attemptAutoReconnectIfNeeded(force: Bool = false) {
        guard !showOnboarding else { return }
        if !force && didAttemptAutoReconnect { return }
        didAttemptAutoReconnect = true
        services.connectionManager.attemptAutoReconnect()
    }
}

/// Theme preference — persisted across launches via @AppStorage
enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case dark = "Dark"
    case light = "Light"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }

    var icon: String {
        switch self {
        case .system: return "gearshape"
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }
}
