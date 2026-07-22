import Foundation
import Combine

/// Local cache + host sync for reviewable Plans.
@MainActor
final class PlanStore: ObservableObject {
    @Published private(set) var plans: [PlanArtifact] = []
    @Published private(set) var templates: [PlanTemplate] = []
    @Published private(set) var lastError: String?

    private let storageKey = "centurion.plans.v1"
    private let templatesKey = "centurion.planTemplates.v1"

    init() {
        load()
    }

    var pendingReview: [PlanArtifact] {
        plans
            .filter { $0.status == .pendingReview || $0.status == .held || $0.status == .adjusted }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var inProgress: [PlanArtifact] {
        plans
            .filter { $0.status == .proceeded }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var completed: [PlanArtifact] {
        plans
            .filter { $0.status == .completed || $0.status == .rejected }
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

    /// Apply a `plan-update` fence from Plan Discuss chat; returns true if applied.
    @discardableResult
    func applyDiscussUpdate(_ payload: PlanDiscussChat.UpdatePayload) -> Bool {
        guard let id = UUID(uuidString: payload.plan_id),
              var plan = plan(id: id) else {
            return false
        }
        if let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            plan.title = title
        }
        if let goal = payload.goal {
            plan.goal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let steps = payload.steps {
            plan.steps = steps
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if let risks = payload.risks {
            plan.risks = risks
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if let questions = payload.open_questions {
            plan.openQuestions = questions
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if let summary = payload.summary {
            plan.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let statusRaw = payload.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !statusRaw.isEmpty {
            plan.status = PlanArtifact.PlanStatus(rawValue: statusRaw)
                ?? decodeStatusAlias(statusRaw)
                ?? plan.status
        }
        upsert(plan)
        return true
    }

    private func decodeStatusAlias(_ raw: String) -> PlanArtifact.PlanStatus? {
        switch raw {
        case "pending_review", "proposed", "pending": return .pendingReview
        case "proceeded", "in_progress", "active": return .proceeded
        case "held", "paused": return .held
        case "adjusted": return .adjusted
        case "completed": return .completed
        case "rejected": return .rejected
        default: return nil
        }
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

    /// Pull host plans + templates when connected.
    func refreshFromHost(connectionManager: ConnectionManager) async {
        guard connectionManager.connectionState == .connected else { return }
        do {
            let remotePlans = try await connectionManager.fetchPlans(status: "all")
            if !remotePlans.isEmpty {
                // Host is source of truth when it has plans; keep purely-local demos otherwise.
                var merged: [PlanArtifact] = remotePlans
                for local in plans where !remotePlans.contains(where: { $0.id == local.id }) {
                    // Keep recent local-only pending plans until push succeeds.
                    if local.status == .pendingReview {
                        merged.append(local)
                    }
                }
                plans = merged.sorted { $0.createdAt > $1.createdAt }
                persist()
            }
            let remoteTemplates = try await connectionManager.fetchPlanTemplates()
            if !remoteTemplates.isEmpty {
                templates = remoteTemplates
                persistTemplates()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Persist a plan locally and push to host when connected.
    func upsertAndSync(_ plan: PlanArtifact, connectionManager: ConnectionManager?) async {
        upsert(plan)
        guard let connectionManager, connectionManager.connectionState == .connected else { return }
        do {
            if let saved = try await connectionManager.putPlan(plan) {
                upsert(saved)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func decide(
        _ id: UUID,
        choice: String,
        connectionManager: ConnectionManager?,
        note: String? = nil
    ) async {
        let localStatus: PlanArtifact.PlanStatus = {
            switch choice.lowercased() {
            case "approve": return .proceeded
            case "reject": return .rejected
            case "request_changes": return .adjusted
            case "hold": return .held
            default: return .pendingReview
            }
        }()
        markStatus(id, status: localStatus)

        guard let connectionManager, connectionManager.connectionState == .connected else { return }
        do {
            if let updated = try await connectionManager.decidePlan(
                planId: id.uuidString,
                choice: choice,
                note: note
            ) {
                upsert(updated)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func share(
        _ id: UUID,
        reviewerCustomerId: String,
        connectionManager: ConnectionManager
    ) async -> Bool {
        do {
            if let updated = try await connectionManager.sharePlan(
                planId: id.uuidString,
                reviewerCustomerId: reviewerCustomerId
            ) {
                upsert(updated)
            }
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func instantiateTemplate(
        _ templateId: String,
        connectionManager: ConnectionManager
    ) async -> PlanArtifact? {
        do {
            let plan = try await connectionManager.instantiatePlanTemplate(templateId: templateId)
            if let plan {
                upsert(plan)
            }
            lastError = nil
            return plan
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(plans) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func persistTemplates() {
        let payload = templates.map { tmpl -> [String: Any] in
            [
                "id": tmpl.id,
                "title": tmpl.title,
                "summary": tmpl.summary,
                "goal": tmpl.goal,
                "steps": tmpl.steps,
                "risks": tmpl.risks,
            ]
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        UserDefaults.standard.set(data, forKey: templatesKey)
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? decoder.decode([PlanArtifact].self, from: data) {
            plans = decoded.sorted { $0.createdAt > $1.createdAt }
        }
        if let data = UserDefaults.standard.data(forKey: templatesKey),
           let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            templates = raw.compactMap(PlanTemplate.decode(from:))
        }
    }
}
