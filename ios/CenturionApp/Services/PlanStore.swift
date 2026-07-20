import Foundation
import Combine

/// Local store of reviewable Plans from Propose first and Pulse mapping.
@MainActor
final class PlanStore: ObservableObject {
    @Published private(set) var plans: [PlanArtifact] = []

    private let storageKey = "centurion.plans.v1"

    init() {
        load()
    }

    var pendingReview: [PlanArtifact] {
        plans
            .filter { $0.status == .pendingReview }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func plan(id: UUID) -> PlanArtifact? {
        plans.first { $0.id == id }
    }

    func upsert(_ plan: PlanArtifact) {
        if let index = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[index] = plan
        } else {
            plans.insert(plan, at: 0)
        }
        persist()
    }

    func markStatus(_ id: UUID, status: PlanArtifact.PlanStatus) {
        guard let index = plans.firstIndex(where: { $0.id == id }) else { return }
        plans[index].status = status
        persist()
    }

    func clearDemoData() {
        plans = []
        persist()
    }

    func seedPreviewIfNeeded(showsDemoContent: Bool) {
        guard showsDemoContent, plans.isEmpty else { return }
        upsert(PlanArtifact.preview())
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(plans) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PlanArtifact].self, from: data) else {
            return
        }
        plans = decoded.sorted { $0.createdAt > $1.createdAt }
    }
}
