import Foundation
import SwiftUI

/// Single source of truth for the user's life mission, soul document, and active targets.
/// Persisted locally — syncs to the Centurion when the remote link is connected (future).
@MainActor
final class MissionStore: ObservableObject {
    @Published private(set) var mission: LifeMission
    @Published private(set) var soul: SoulDocument
    @Published var activeTargetIDs: Set<UUID>

    private static let missionKey = "centurion.lifeMission.v1"
    private static let soulKey = "centurion.soulDocument.v1"
    private static let activeTargetsKey = "centurion.activeMissionTargets"
    private static let discoveryAnswersKey = "centurion.missionDiscoveryAnswers.v1"
    private static let hasPersistedKey = "centurion.mission.hasPersisted"

    @Published private(set) var discoveryAnswers: [String: String] = [:]

    init() {
        let hasPersisted = UserDefaults.standard.bool(forKey: Self.hasPersistedKey)

        let resolvedMission: LifeMission
        if let loaded = Self.loadMission() {
            resolvedMission = loaded
        } else {
            resolvedMission = LifeMission(id: UUID(), statement: "", targets: [])
        }
        mission = resolvedMission

        if let loaded = Self.loadSoul() {
            soul = loaded
        } else {
            soul = SoulDocument()
        }

        if let ids = Self.loadActiveTargetIDs() {
            activeTargetIDs = ids
        } else {
            activeTargetIDs = []
        }

        discoveryAnswers = Self.loadDiscoveryAnswers() ?? [:]
        syncMissionStatementFromSoul()
    }

    // MARK: - Public API

    var hasDiscoveryAnswers: Bool {
        discoveryAnswers.values.contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var activeTargets: [LifeMissionTarget] {
        mission.targets.filter { activeTargetIDs.contains($0.id) }
    }

    var hasMissionStatement: Bool {
        !mission.statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func toggleActiveTarget(_ id: UUID) {
        if activeTargetIDs.contains(id) {
            activeTargetIDs.remove(id)
        } else {
            activeTargetIDs.insert(id)
        }
        persistActiveTargets()
        markPersisted()
    }

    func isTargetActive(_ id: UUID) -> Bool {
        activeTargetIDs.contains(id)
    }

    func completeDiscovery(from answers: [String: String]) {
        discoveryAnswers = answers
        persistDiscoveryAnswers()

        var document = soul
        document.updatedAt = Date()

        if let approved = answers["_missionStatement"]?.trimmingCharacters(in: .whitespacesAndNewlines), !approved.isEmpty {
            document.missionStatement = approved
        } else if let statement = Self.synthesizedMissionStatement(from: answers) {
            document.missionStatement = statement
        }
        if let approvedWhy = answers["_whyThisMission"]?.trimmingCharacters(in: .whitespacesAndNewlines), !approvedWhy.isEmpty {
            document.whyThisMission = approvedWhy
        } else if let why = Self.synthesizedWhy(from: answers) {
            document.whyThisMission = why
        }
        if let focus = Self.synthesizedFocusAreas(from: answers), !focus.isEmpty {
            document.areasOfFocus = focus
        }
        if let goals = Self.synthesizedGoals(from: answers), !goals.isEmpty {
            document.goals = goals
        }

        completeDiscovery(with: document)
    }

    func completeDiscovery(with document: SoulDocument) {
        soul = document
        persistSoul()

        if !document.missionStatement.isEmpty {
            mission.statement = document.missionStatement
        }

        if !document.goals.isEmpty {
            mission.targets = document.goals.map { goal in
                LifeMissionTarget(
                    id: UUID(),
                    title: goal,
                    description: document.whyThisMission.isEmpty
                        ? "A commitment your Centurion is helping you fulfill."
                        : document.whyThisMission
                )
            }
            activeTargetIDs = Set(mission.targets.map(\.id))
            persistActiveTargets()
        }

        persistMission()
        markPersisted()
    }

    func updateSoul(_ document: SoulDocument) {
        soul = document
        persistSoul()
        syncMissionStatementFromSoul()
        markPersisted()
    }

    // MARK: - Persistence

    private func syncMissionStatementFromSoul() {
        let statement = soul.missionStatement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !statement.isEmpty, statement != mission.statement else { return }
        mission.statement = statement
        persistMission()
    }

    private func markPersisted() {
        UserDefaults.standard.set(true, forKey: Self.hasPersistedKey)
    }

    private func persistMission() {
        guard let data = try? JSONEncoder().encode(mission) else { return }
        UserDefaults.standard.set(data, forKey: Self.missionKey)
    }

    private func persistSoul() {
        guard let data = try? JSONEncoder().encode(soul) else { return }
        UserDefaults.standard.set(data, forKey: Self.soulKey)
    }

    private func persistActiveTargets() {
        let strings = activeTargetIDs.map(\.uuidString)
        UserDefaults.standard.set(strings, forKey: Self.activeTargetsKey)
    }

    private static func loadMission() -> LifeMission? {
        guard let data = UserDefaults.standard.data(forKey: missionKey),
              let mission = try? JSONDecoder().decode(LifeMission.self, from: data) else {
            return nil
        }
        return mission
    }

    private static func loadSoul() -> SoulDocument? {
        guard let data = UserDefaults.standard.data(forKey: soulKey),
              let soul = try? JSONDecoder().decode(SoulDocument.self, from: data) else {
            return nil
        }
        return soul
    }

    private static func loadActiveTargetIDs() -> Set<UUID>? {
        guard let strings = UserDefaults.standard.stringArray(forKey: activeTargetsKey) else {
            return nil
        }
        return Set(strings.compactMap(UUID.init(uuidString:)))
    }

    private func persistDiscoveryAnswers() {
        guard let data = try? JSONEncoder().encode(discoveryAnswers) else { return }
        UserDefaults.standard.set(data, forKey: Self.discoveryAnswersKey)
    }

    private static func loadDiscoveryAnswers() -> [String: String]? {
        guard let data = UserDefaults.standard.data(forKey: discoveryAnswersKey),
              let answers = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return answers
    }

    // MARK: - Discovery synthesis

    static func synthesizedMissionStatement(from answers: [String: String]) -> String? {
        nonEmptyAnswer(from: answers, keys: ["_missionStatement", "endOfLife", "noLimits", "shouldDo"])
    }

    static func synthesizedWhy(from answers: [String: String]) -> String? {
        nonEmptyAnswer(from: answers, keys: ["_whyThisMission", "shouldDo", "responsibility", "alive"])
    }

    private static func synthesizedFocusAreas(from answers: [String: String]) -> [String]? {
        if let top = nonEmptyAnswer(from: answers, keys: ["topAreas"]) {
            return splitList(top)
        }
        if let areas = nonEmptyAnswer(from: answers, keys: ["areas"]) {
            return splitList(areas)
        }
        return nil
    }

    private static func synthesizedGoals(from answers: [String: String]) -> [String]? {
        var goals: [String] = []
        if let top = nonEmptyAnswer(from: answers, keys: ["topAreas"]) {
            goals.append(contentsOf: splitList(top))
        }
        if let problems = nonEmptyAnswer(from: answers, keys: ["problems"]) {
            goals.append(contentsOf: splitList(problems))
        }
        if let responsibility = nonEmptyAnswer(from: answers, keys: ["responsibility"]) {
            goals.append(responsibility)
        }
        let unique = Array(Set(goals.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
        return unique.isEmpty ? nil : Array(unique.prefix(5))
    }

    private static func nonEmptyAnswer(from answers: [String: String], keys: [String]) -> String? {
        for key in keys {
            let value = answers[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static func splitList(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\n", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func discoveryShareMessage(answers: [String: String], questions: [MissionQuestion]) -> String {
        var lines = ["I've completed my Mission Discovery on Centurion Remote.", ""]
        for question in questions {
            guard let answer = answers[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !answer.isEmpty else { continue }
            lines.append("**\(question.section)**")
            lines.append(question.question)
            lines.append(answer)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
