import Foundation
import SwiftUI

/// Single source of truth for the human's mission and the Centurion's Soul.
/// Mission = you. Soul = your AI companion's personality and rules.
@MainActor
final class MissionStore: ObservableObject {
    @Published private(set) var mission: LifeMission
    @Published private(set) var soul: SoulDocument
    @Published var activeTargetIDs: Set<UUID>

    private static let missionKey = "centurion.lifeMission.v1"
    private static let soulKey = "centurion.soulDocument.v1"
    private static let legacySoulKey = "centurion.soulDocument.v1"
    private static let activeTargetsKey = "centurion.activeMissionTargets"
    private static let discoveryAnswersKey = "centurion.missionDiscoveryAnswers.v1"
    private static let hasPersistedKey = "centurion.mission.hasPersisted"
    private static let migrationKey = "centurion.soulMissionSplit.v1"

    @Published private(set) var discoveryAnswers: [String: String] = [:]

    init() {
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

        if !UserDefaults.standard.bool(forKey: Self.migrationKey) {
            runLegacyMigration()
            UserDefaults.standard.set(true, forKey: Self.migrationKey)
        }
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

    var hasSoulConfiguration: Bool {
        soul.isValid
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

        var updated = mission

        if let approved = answers["_missionStatement"]?.trimmingCharacters(in: .whitespacesAndNewlines), !approved.isEmpty {
            updated.statement = approved
        } else if let statement = Self.synthesizedMissionStatement(from: answers) {
            updated.statement = statement
        }

        if let approvedWhy = answers["_whyThisMission"]?.trimmingCharacters(in: .whitespacesAndNewlines), !approvedWhy.isEmpty {
            updated.profile.whyThisMission = approvedWhy
        } else if let why = Self.synthesizedWhy(from: answers) {
            updated.profile.whyThisMission = why
        }

        if let focus = Self.synthesizedFocusAreas(from: answers), !focus.isEmpty {
            updated.profile.areasOfFocus = focus
        }

        if let goals = Self.synthesizedGoals(from: answers), !goals.isEmpty {
            updated.targets = goals.map { goal in
                LifeMissionTarget(
                    id: UUID(),
                    title: goal,
                    description: updated.profile.whyThisMission.isEmpty
                        ? "A commitment your Centurion is helping you fulfill."
                        : updated.profile.whyThisMission
                )
            }
            activeTargetIDs = Set(updated.targets.map(\.id))
            persistActiveTargets()
        }

        mission = updated
        persistMission()
        markPersisted()
    }

    func updateProfile(_ profile: HumanProfile) {
        mission.profile = profile
        persistMission()
        markPersisted()
    }

    func updateSoul(_ document: SoulDocument) {
        var updated = document
        updated.updatedAt = Date()
        if updated.version < 2 { updated.version = 2 }
        soul = updated
        persistSoul()
        markPersisted()
    }

    // MARK: - Legacy migration

    private func runLegacyMigration() {
        guard let data = UserDefaults.standard.data(forKey: Self.legacySoulKey),
              let legacy = try? JSONDecoder().decode(LegacySoulDocument.self, from: data) else {
            return
        }

        var updatedMission = mission

        if updatedMission.statement.isEmpty, !legacy.missionStatement.isEmpty {
            updatedMission.statement = legacy.missionStatement
        }

        if updatedMission.profile.whyThisMission.isEmpty, !legacy.whyThisMission.isEmpty {
            updatedMission.profile.whyThisMission = legacy.whyThisMission
        }
        if updatedMission.profile.areasOfFocus.isEmpty, !legacy.areasOfFocus.isEmpty {
            updatedMission.profile.areasOfFocus = legacy.areasOfFocus
        }
        if updatedMission.profile.yourStory.isEmpty, !legacy.yourStory.isEmpty {
            updatedMission.profile.yourStory = legacy.yourStory
        }
        if updatedMission.profile.yourValues.isEmpty, !legacy.yourValues.isEmpty {
            updatedMission.profile.yourValues = legacy.yourValues
        }
        if updatedMission.profile.yourPersonality.isEmpty, !legacy.yourPersonality.isEmpty {
            updatedMission.profile.yourPersonality = legacy.yourPersonality
        }
        if updatedMission.profile.yourStrengths.isEmpty, !legacy.yourStrengths.isEmpty {
            updatedMission.profile.yourStrengths = legacy.yourStrengths
        }
        if updatedMission.profile.vitalStatName.isEmpty, !legacy.vitalStatName.isEmpty {
            updatedMission.profile.vitalStatName = legacy.vitalStatName
            updatedMission.profile.vitalStatCurrent = legacy.vitalStatCurrent
            updatedMission.profile.vitalStatTarget = legacy.vitalStatTarget
        }
        if updatedMission.profile.workStyle.isEmpty, !legacy.workStyle.isEmpty {
            updatedMission.profile.workStyle = legacy.workStyle
        }
        if updatedMission.profile.decisionStyle.isEmpty, !legacy.decisionStyle.isEmpty {
            updatedMission.profile.decisionStyle = legacy.decisionStyle
        }
        if updatedMission.profile.timezone.isEmpty, !legacy.timezone.isEmpty {
            updatedMission.profile.timezone = legacy.timezone
        }
        if updatedMission.profile.workHours.isEmpty, !legacy.workHours.isEmpty {
            updatedMission.profile.workHours = legacy.workHours
        }
        if updatedMission.profile.challenges.isEmpty, !legacy.challenges.isEmpty {
            updatedMission.profile.challenges = legacy.challenges
        }
        if updatedMission.profile.keyRelationships.isEmpty, !legacy.keyRelationships.isEmpty {
            updatedMission.profile.keyRelationships = legacy.keyRelationships
        }
        if updatedMission.profile.toolsYouUse.isEmpty, !legacy.toolsYouUse.isEmpty {
            updatedMission.profile.toolsYouUse = legacy.toolsYouUse
        }
        if updatedMission.profile.delegatePreferences.isEmpty, !legacy.delegatePreferences.isEmpty {
            updatedMission.profile.delegatePreferences = legacy.delegatePreferences
        }
        if updatedMission.profile.currentProjects.isEmpty, !legacy.currentProjects.isEmpty {
            updatedMission.profile.currentProjects = legacy.currentProjects
        }

        if updatedMission.targets.isEmpty, !legacy.goals.isEmpty {
            updatedMission.targets = legacy.goals.map { goal in
                LifeMissionTarget(
                    id: UUID(),
                    title: goal,
                    description: legacy.whyThisMission.isEmpty
                        ? "A commitment your Centurion is helping you fulfill."
                        : legacy.whyThisMission
                )
            }
            if activeTargetIDs.isEmpty {
                activeTargetIDs = Set(updatedMission.targets.map(\.id))
                persistActiveTargets()
            }
        }

        mission = updatedMission
        persistMission()

        if !soul.isValid {
            var migratedSoul = soul
            migratedSoul.version = 2
            if migratedSoul.personalitySummary.isEmpty {
                let parts = [legacy.preferredTone, legacy.feedbackPreference]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !parts.isEmpty {
                    migratedSoul.personalitySummary = parts.joined(separator: ". ")
                }
            }
            if migratedSoul.tone.isEmpty, !legacy.preferredTone.isEmpty {
                migratedSoul.tone = legacy.preferredTone
            }
            if migratedSoul.communicationStyle.isEmpty, !legacy.communicationStyle.isEmpty {
                migratedSoul.communicationStyle = legacy.communicationStyle
            }
            if migratedSoul.pushbackStyle.isEmpty, !legacy.feedbackPreference.isEmpty {
                migratedSoul.pushbackStyle = legacy.feedbackPreference
            }
            soul = migratedSoul
            persistSoul()
        }
    }

    // MARK: - Persistence

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
        guard let data = UserDefaults.standard.data(forKey: soulKey) else { return nil }
        if let soul = try? JSONDecoder().decode(SoulDocument.self, from: data) {
            return soul
        }
        return nil
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
