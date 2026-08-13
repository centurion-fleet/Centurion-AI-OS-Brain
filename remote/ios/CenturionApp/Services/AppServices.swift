import SwiftUI

/// App-wide services — created after the first splash frame so launch stays instant.
@MainActor
final class AppServices: ObservableObject {
    let connectionManager: ConnectionManager
    let messageService: MessageService
    let missionStore: MissionStore
    let dataMode: AppDataMode
    let adrianService: AdrianService
    let swarmStore: SwarmStore
    let planStore: PlanStore
    let beneficiaryStore: BeneficiaryStore
    let oversightStore: OversightStore
    let memoryHorizonStore: MemoryHorizonStore

    init() {
        let connectionManager = ConnectionManager()
        let dataMode = AppDataMode()
        self.connectionManager = connectionManager
        self.dataMode = dataMode
        self.messageService = MessageService(connectionManager: connectionManager, dataMode: dataMode)
        self.missionStore = MissionStore()
        self.adrianService = AdrianService()
        self.swarmStore = SwarmStore()
        self.planStore = PlanStore()
        self.beneficiaryStore = BeneficiaryStore()
        self.oversightStore = OversightStore()
        self.memoryHorizonStore = MemoryHorizonStore()
        dataMode.update(connectionState: connectionManager.connectionState)
    }
}
