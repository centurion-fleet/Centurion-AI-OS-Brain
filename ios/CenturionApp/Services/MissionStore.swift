import Foundation
import SwiftUI

/// Single source of truth for the human's mission and the Sovereign's Soul.
/// Mission = you. Soul = your AI companion's personality and rules.
@MainActor
final class MissionStore: ObservableObject {
    @Published private(set) var mission: LifeMission
    @Published private(set) var soul: SoulDocument
    @Published private(set) var soulSyncedWithSovereign = false
    @Published private(set) var missionSyncedWithSovereign = false
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

        var resolvedSoul: SoulDocument
        if let loaded = Self.loadSoul() {
            resolvedSoul = loaded
        } else {
            resolvedSoul = SoulDocument()
        }
        let beforeAlwaysDo = resolvedSoul.alwaysDo
        if resolvedSoul.isValid {
            resolvedSoul.ensureProposeFirstStandingRule()
        }
        soul = resolvedSoul

        if let ids = Self.loadActiveTargetIDs() {
            activeTargetIDs = ids
        } else {
            activeTargetIDs = []
        }

        discoveryAnswers = Self.loadDiscoveryAnswers() ?? [:]

        if beforeAlwaysDo != resolvedSoul.alwaysDo {
            persistSoul()
        }

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

    var soulSubtitle: String {
        if !hasSoulConfiguration {
            return "Personality and rules for your AI"
        }
        return soulSyncedWithSovereign
            ? "Personality and rules configured"
            : "On this phone — link to sync"
    }

    var missionSubtitle: String {
        if !hasMissionStatement {
            return "Your north star — syncs to your Sovereign"
        }
        return missionSyncedWithSovereign
            ? "Synced — shapes the next conversation"
            : "On this phone — link to sync"
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
                        ? "A commitment your Sovereign is helping you fulfill."
                        : updated.profile.whyThisMission
                )
            }
            activeTargetIDs = Set(updated.targets.map(\.id))
            persistActiveTargets()
        }

        mission = updated
        persistMission()
        markPersisted()
        missionSyncedWithSovereign = false
    }

    func updateProfile(_ profile: HumanProfile) {
        mission.profile = profile
        persistMission()
        markPersisted()
        missionSyncedWithSovereign = false
    }

    func commitment(with id: UUID) -> LifeMissionTarget? {
        mission.targets.first { $0.id == id }
    }

    @discardableResult
    func applyCommitmentUpdate(_ payload: MissionCommitmentChat.UpdatePayload) -> Bool {
        guard let id = UUID(uuidString: payload.commitment_id),
              let index = mission.targets.firstIndex(where: { $0.id == id }) else {
            return false
        }

        if let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            mission.targets[index].title = title
        }
        if let description = payload.description?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            mission.targets[index].description = description
        }
        if let active = payload.active {
            if active {
                activeTargetIDs.insert(id)
            } else {
                activeTargetIDs.remove(id)
            }
            persistActiveTargets()
        }

        persistMission()
        markPersisted()
        missionSyncedWithSovereign = false
        return true
    }

    func updateSoul(_ document: SoulDocument) {
        var updated = document
        updated.ensureProposeFirstStandingRule()
        updated.updatedAt = Date()
        if updated.version < 2 { updated.version = 2 }
        soul = updated
        soulSyncedWithSovereign = false
        persistSoul()
        markPersisted()
    }

    /// Pull host SOUL.md into the local structured document when linked.
    func refreshSoul(from connectionManager: ConnectionManager) async {
        guard connectionManager.connectionState == .connected else { return }
        do {
            let payload = try await connectionManager.fetchSoul()
            if let merged = Self.soulDocument(fromHost: payload) {
                // Prefer host when local is empty; otherwise keep local edits until push.
                if !soul.isValid || Self.hostLooksRicher(payload, than: soul) {
                    soul = merged
                    persistSoul()
                    markPersisted()
                }
                soulSyncedWithSovereign = true
            }
        } catch {
            // Offline / bridge failure — keep local cache.
        }
    }

    /// Push local Soul to the Sovereign after an explicit user confirmation.
    @discardableResult
    func syncSoulToSovereign(connectionManager: ConnectionManager) async -> String? {
        guard connectionManager.connectionState == .connected else {
            return "Saved on this phone. Link your Sovereign to sync."
        }
        do {
            let fields: [String: Any] = [
                "name": soul.name,
                "personalitySummary": soul.personalitySummary,
                "tone": soul.tone,
                "communicationStyle": soul.communicationStyle,
                "pushbackStyle": soul.pushbackStyle,
                "alwaysDo": soul.alwaysDo,
                "neverDo": soul.neverDo,
                "uncertaintyStyle": soul.uncertaintyStyle,
                "responseLength": soul.responseLength,
            ]
            let payload = try await connectionManager.putSoul(fields)
            if let merged = Self.soulDocument(fromHost: payload) {
                soul = merged
                persistSoul()
            }
            soulSyncedWithSovereign = true
            markPersisted()
            return "Saved. Soul changes apply on the next conversation."
        } catch {
            return error.localizedDescription
        }
    }

    /// Pull host LIFE_MISSION.md into the local LifeMission when linked.
    func refreshMission(from connectionManager: ConnectionManager) async {
        guard connectionManager.connectionState == .connected else { return }
        do {
            let payload = try await connectionManager.fetchMission()
            if let merged = Self.lifeMission(fromHost: payload) {
                if !hasMissionStatement || Self.hostMissionLooksRicher(payload, than: mission) {
                    mission = merged
                    persistMission()
                    markPersisted()
                }
                missionSyncedWithSovereign = true
            }
        } catch {
            // Offline / bridge failure — keep local cache.
        }
    }

    /// Push local Life Mission to the Sovereign (LIFE_MISSION.md + USER.md).
    @discardableResult
    func syncMissionToSovereign(connectionManager: ConnectionManager) async -> String? {
        guard connectionManager.connectionState == .connected else {
            return "Saved on this phone. Link your Sovereign to sync."
        }
        guard hasMissionStatement else {
            return "Set a Life Mission statement before syncing."
        }
        do {
            let fields = missionPayloadDictionary()
            let payload = try await connectionManager.putMission(fields)
            if let merged = Self.lifeMission(fromHost: payload) {
                mission = merged
                persistMission()
            }
            missionSyncedWithSovereign = true
            markPersisted()
            return "Saved. Life Mission shapes the next conversation."
        } catch {
            return error.localizedDescription
        }
    }

    func missionPayloadDictionary() -> [String: Any] {
        let profile = mission.profile
        return [
            "id": mission.id.uuidString,
            "statement": mission.statement,
            "targets": mission.targets.map { target -> [String: Any] in
                [
                    "id": target.id.uuidString,
                    "title": target.title,
                    "description": target.description,
                ]
            },
            "profile": [
                "whyThisMission": profile.whyThisMission,
                "areasOfFocus": profile.areasOfFocus,
                "yourStory": profile.yourStory,
                "yourValues": profile.yourValues,
                "yourPersonality": profile.yourPersonality,
                "yourStrengths": profile.yourStrengths,
                "vitalStatName": profile.vitalStatName,
                "vitalStatCurrent": profile.vitalStatCurrent,
                "vitalStatTarget": profile.vitalStatTarget,
                "workStyle": profile.workStyle,
                "decisionStyle": profile.decisionStyle,
                "timezone": profile.timezone,
                "workHours": profile.workHours,
                "challenges": profile.challenges,
                "keyRelationships": profile.keyRelationships,
                "toolsYouUse": profile.toolsYouUse,
                "delegatePreferences": profile.delegatePreferences,
                "currentProjects": profile.currentProjects,
            ] as [String: Any],
        ]
    }

    private static func lifeMission(fromHost payload: [String: Any]) -> LifeMission? {
        let statement = (payload["statement"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let idString = payload["id"] as? String ?? ""
        let id = UUID(uuidString: idString) ?? UUID()
        var profile = HumanProfile()
        if let p = payload["profile"] as? [String: Any] {
            profile.whyThisMission = p["whyThisMission"] as? String ?? ""
            profile.areasOfFocus = p["areasOfFocus"] as? [String] ?? []
            profile.yourStory = p["yourStory"] as? String ?? ""
            profile.yourValues = p["yourValues"] as? [String] ?? []
            profile.yourPersonality = p["yourPersonality"] as? String ?? ""
            profile.yourStrengths = p["yourStrengths"] as? [String] ?? []
            profile.workStyle = p["workStyle"] as? String ?? ""
            profile.decisionStyle = p["decisionStyle"] as? String ?? ""
            profile.challenges = p["challenges"] as? [String] ?? []
            profile.keyRelationships = p["keyRelationships"] as? [String] ?? []
            profile.toolsYouUse = p["toolsYouUse"] as? [String] ?? []
            profile.delegatePreferences = p["delegatePreferences"] as? [String] ?? []
            profile.currentProjects = p["currentProjects"] as? [String] ?? []
            profile.timezone = p["timezone"] as? String ?? ""
            profile.workHours = p["workHours"] as? String ?? ""
            profile.vitalStatName = p["vitalStatName"] as? String ?? ""
            if let v = p["vitalStatCurrent"] as? Double { profile.vitalStatCurrent = v }
            if let v = p["vitalStatTarget"] as? Double { profile.vitalStatTarget = v }
        }
        var targets: [LifeMissionTarget] = []
        if let raw = payload["targets"] as? [[String: Any]] {
            for item in raw {
                let title = (item["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                let tid = UUID(uuidString: item["id"] as? String ?? "") ?? UUID()
                targets.append(
                    LifeMissionTarget(
                        id: tid,
                        title: title,
                        description: item["description"] as? String ?? ""
                    )
                )
            }
        }
        if statement.isEmpty && targets.isEmpty && !profile.hasContext {
            return nil
        }
        return LifeMission(id: id, statement: statement, targets: targets, profile: profile)
    }

    private static func hostMissionLooksRicher(_ payload: [String: Any], than local: LifeMission) -> Bool {
        let hostStatement = (payload["statement"] as? String ?? "").count
        let hostTargets = (payload["targets"] as? [[String: Any]] ?? []).count
        let localScore = local.statement.count + local.targets.count
        return (hostStatement + hostTargets * 20) > localScore
    }

    private static func soulDocument(fromHost payload: [String: Any]) -> SoulDocument? {
        var doc = SoulDocument()
        doc.name = payload["name"] as? String ?? ""
        doc.personalitySummary = payload["personalitySummary"] as? String ?? ""
        doc.tone = payload["tone"] as? String ?? ""
        doc.communicationStyle = payload["communicationStyle"] as? String ?? ""
        doc.pushbackStyle = payload["pushbackStyle"] as? String ?? ""
        doc.alwaysDo = payload["alwaysDo"] as? [String] ?? []
        doc.neverDo = payload["neverDo"] as? [String] ?? []
        doc.uncertaintyStyle = payload["uncertaintyStyle"] as? String ?? ""
        doc.responseLength = payload["responseLength"] as? String ?? ""
        doc.updatedAt = Date()
        doc.version = 2
        return doc.isValid || !(payload["markdown"] as? String ?? "").isEmpty ? doc : nil
    }

    private static func hostLooksRicher(_ payload: [String: Any], than local: SoulDocument) -> Bool {
        let hostName = (payload["name"] as? String ?? "").count
        let hostSummary = (payload["personalitySummary"] as? String ?? "").count
        let hostAlways = (payload["alwaysDo"] as? [String] ?? []).count
        let hostNever = (payload["neverDo"] as? [String] ?? []).count
        let localScore = local.name.count + local.personalitySummary.count + local.alwaysDo.count + local.neverDo.count
        return (hostName + hostSummary + hostAlways + hostNever) > localScore
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
                        ? "A commitment your Sovereign is helping you fulfill."
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
        var lines = ["I've completed my Mission Discovery on Sovereign AI Remote.", ""]
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
