import SwiftUI

@main
struct CenturionApp: App {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("centurion.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showSplash = true
    @State private var showOnboarding = false
    @State private var services = AppServices()
    @State private var clearedDemoForConnection = false

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
                    }
                    .transition(.opacity)
                    .zIndex(2)
                }

                if showOnboarding {
                    WelcomeOnboardingView {
                        withAnimation(.easeOut(duration: 0.25)) {
                            showOnboarding = false
                        }
                    }
                    .environmentObject(services.connectionManager)
                    .environmentObject(services.missionStore)
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .preferredColorScheme(appearanceMode.colorScheme)
            .onReceive(services.connectionManager.$connectionState) { state in
                services.dataMode.update(connectionState: state)
                if state == .connected {
                    if !clearedDemoForConnection {
                        services.messageService.clearDemoData()
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
