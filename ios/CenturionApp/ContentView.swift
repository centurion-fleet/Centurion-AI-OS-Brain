import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ConversationListView()
                .tabItem {
                    Label("Chat", systemImage: "message.fill")
                }
                .tag(0)
            
            ConnectionView()
                .tabItem {
                    Label("Connect", systemImage: connectionManager.connectionState == .connected
                          ? "antenna.radiowaves.left.and.right.fill"
                          : "antenna.radiowaves.left.and.right")
                }
                .tag(1)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .tint(Color(red: 1.0, green: 0.84, blue: 0.0)) // Centurion gold
    }
}
