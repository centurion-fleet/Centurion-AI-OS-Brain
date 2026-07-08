import SwiftUI

@main
struct CenturionApp: App {
    @StateObject private var connectionManager = ConnectionManager()
    @StateObject private var messageService: MessageService
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    
    init() {
        let cm = ConnectionManager()
        _connectionManager = StateObject(wrappedValue: cm)
        _messageService = StateObject(wrappedValue: MessageService(connectionManager: cm))
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectionManager)
                .environmentObject(messageService)
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
