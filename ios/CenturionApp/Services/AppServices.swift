import SwiftUI

/// App-wide services — created after the first splash frame so launch stays instant.
@MainActor
final class AppServices: ObservableObject {
    let connectionManager: ConnectionManager
    let messageService: MessageService
    let missionStore: MissionStore

    init() {
        let connectionManager = ConnectionManager()
        self.connectionManager = connectionManager
        self.messageService = MessageService(connectionManager: connectionManager)
        self.missionStore = MissionStore()
    }
}
