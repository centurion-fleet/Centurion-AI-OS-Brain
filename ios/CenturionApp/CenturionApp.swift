import SwiftUI

@main
struct CenturionApp: App {
    @StateObject private var connectionManager = ConnectionManager()
    @StateObject private var messageService: MessageService
    
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
                .preferredColorScheme(.dark)
        }
    }
}
