import SwiftUI

@main
struct CenturionApp: App {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @State private var showSplash = true
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            ZStack {
                ColorTheme.background()
                    .ignoresSafeArea()

                ContentView()
                    .environmentObject(services.connectionManager)
                    .environmentObject(services.messageService)
                    .environmentObject(services.missionStore)
                    .opacity(showSplash ? 0 : 1)
                    .allowsHitTesting(!showSplash)

                if showSplash {
                    SplashView {
                        withAnimation(.easeOut(duration: 0.25)) {
                            showSplash = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .preferredColorScheme(appearanceMode.colorScheme)
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
