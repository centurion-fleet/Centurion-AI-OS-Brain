import SwiftUI

@main
struct CenturionApp: App {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("centurion.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true
    @State private var showOnboarding = false
    @State private var services = AppServices()
    @State private var clearedDemoForConnection = false
    @State private var didAttemptAutoReconnect = false

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
                    .environmentObject(services.beneficiaryStore)
                    .opacity(showSplash || showOnboarding ? 0 : 1)
                    .allowsHitTesting(!showSplash && !showOnboarding)

                if showSplash {
                    SplashView {
                        withAnimation(.easeOut(duration: 0.25)) {
                            showSplash = false
                            showOnboarding = !hasCompletedOnboarding
                        }
                        attemptAutoReconnectIfNeeded()
                    }
                    .transition(.opacity)
                    .zIndex(2)
                }

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
                    .zIndex(1)
                }
            }
            .preferredColorScheme(appearanceMode.colorScheme)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    attemptAutoReconnectIfNeeded(force: true)
                }
            }
            .onReceive(services.connectionManager.$connectionState) { state in
                services.dataMode.update(connectionState: state)
                if state == .connected {
                    if !clearedDemoForConnection {
                        services.messageService.clearDemoData()
                        ConversationStore.shared.restore(into: services.messageService)
                        clearedDemoForConnection = true
                    }
                    Task {
                        await services.swarmStore.refresh(from: services.connectionManager)
                        await services.beneficiaryStore.refresh(from: services.connectionManager)
                    }
                } else {
                    clearedDemoForConnection = false
                }
            }
        }
    }

    private func attemptAutoReconnectIfNeeded(force: Bool = false) {
        guard !showSplash else { return }
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
