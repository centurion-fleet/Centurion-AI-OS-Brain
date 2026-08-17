import Foundation

// MARK: - Subjects

/// Top-level life area (Health, Work, …). Brain `life_subjects` row.
struct MissionSubject: Identifiable, Decodable, Equatable, Hashable {
    let id: UUID
    var name: String
    var icon: String
    var sortOrder: Int
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, icon
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "list.bullet",
        sortOrder: Int = 0,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let u = try? c.decode(UUID.self, forKey: .id) {
            id = u
        } else {
            let s = try c.decode(String.self, forKey: .id)
            id = UUID(uuidString: s) ?? UUID()
        }
        name = try c.decode(String.self, forKey: .name)
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "list.bullet"
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

// MARK: - Dreams

/// Aspiration not yet a Mission. Promote → supporting mission.
struct MissionDream: Identifiable, Decodable, Equatable, Hashable {
    let id: UUID
    var title: String
    var description: String
    var sortOrder: Int
    var promotedToMissionId: UUID?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description
        case sortOrder = "sort_order"
        case promotedToMissionId = "promoted_to_mission_id"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let u = try? c.decode(UUID.self, forKey: .id) {
            id = u
        } else {
            let s = try c.decode(String.self, forKey: .id)
            id = UUID(uuidString: s) ?? UUID()
        }
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        if let u = try? c.decodeIfPresent(UUID.self, forKey: .promotedToMissionId) {
            promotedToMissionId = u
        } else if let s = try c.decodeIfPresent(String.self, forKey: .promotedToMissionId) {
            promotedToMissionId = UUID(uuidString: s)
        } else {
            promotedToMissionId = nil
        }
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

// MARK: - Mission detail (Brain life_missions)

enum MissionPhase: String, Codable, CaseIterable {
    case briefing, discovery, planning, executing, verifying, done

    var label: String {
        switch self {
        case .briefing: return "Briefing"
        case .discovery: return "Discovery"
        case .planning: return "Planning"
        case .executing: return "Executing"
        case .verifying: return "Verifying"
        case .done: return "Done"
        }
    }
}

enum MissionKind: String, Codable {
    case primary, supporting, dream
}

enum TargetKind: String, Codable, CaseIterable {
    case essential
    case shouldHave
    case niceToHave

    var label: String {
        switch self {
        case .essential: return "Must Do"
        case .shouldHave: return "Should Do"
        case .niceToHave: return "Nice to Do"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "essential", "must": self = .essential
        case "shouldHave", "should": self = .shouldHave
        case "niceToHave", "nice": self = .niceToHave
        default: self = .essential
        }
    }
}

enum TargetStatus: String, Codable {
    case notStarted = "not_started"
    case inProgress = "in_progress"
    case complete
    case blocked
}

struct MissionTargetDetail: Identifiable, Decodable, Equatable, Hashable {
    let id: UUID
    var missionId: UUID?
    var sequenceNumber: Int
    var title: String
    var description: String
    var targetType: TargetKind
    var status: TargetStatus
    var focusTarget: Bool
    var sequenceWarning: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description, status
        case missionId = "mission_id"
        case sequenceNumber = "sequence_number"
        case targetType = "target_type"
        case focusTarget = "focus_target"
        case sequenceWarning = "sequence_warning"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try Self.decodeUUID(c, forKey: .id)
        missionId = try Self.decodeOptionalUUID(c, forKey: .missionId)
        sequenceNumber = try c.decodeIfPresent(Int.self, forKey: .sequenceNumber) ?? 0
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        targetType = try c.decodeIfPresent(TargetKind.self, forKey: .targetType) ?? .essential
        status = try c.decodeIfPresent(TargetStatus.self, forKey: .status) ?? .notStarted
        if let flag = try c.decodeIfPresent(Bool.self, forKey: .focusTarget) {
            focusTarget = flag
        } else if let n = try c.decodeIfPresent(Int.self, forKey: .focusTarget) {
            focusTarget = n != 0
        } else {
            focusTarget = false
        }
        sequenceWarning = try c.decodeIfPresent(String.self, forKey: .sequenceWarning)
    }

    private static func decodeUUID(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> UUID {
        if let u = try? c.decode(UUID.self, forKey: key) { return u }
        let s = try c.decode(String.self, forKey: key)
        return UUID(uuidString: s) ?? UUID()
    }

    private static func decodeOptionalUUID(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> UUID? {
        if let u = try? c.decodeIfPresent(UUID.self, forKey: key) { return u }
        if let s = try c.decodeIfPresent(String.self, forKey: key) { return UUID(uuidString: s) }
        return nil
    }
}

struct MissionState: Decodable, Equatable {
    var missionId: UUID?
    var focusTargetId: UUID?
    var completedTargetIds: [UUID]
    var lastActivityAt: String?
    var lastDecisionId: UUID?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case missionId = "mission_id"
        case focusTargetId = "focus_target_id"
        case completedTargetIds = "completed_target_ids"
        case lastActivityAt = "last_activity_at"
        case lastDecisionId = "last_decision_id"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        missionId = Self.optionalUUID(c, .missionId)
        focusTargetId = Self.optionalUUID(c, .focusTargetId)
        if let ids = try? c.decode([UUID].self, forKey: .completedTargetIds) {
            completedTargetIds = ids
        } else if let raw = try? c.decode([String].self, forKey: .completedTargetIds) {
            completedTargetIds = raw.compactMap(UUID.init(uuidString:))
        } else {
            completedTargetIds = []
        }
        lastActivityAt = try c.decodeIfPresent(String.self, forKey: .lastActivityAt)
        lastDecisionId = Self.optionalUUID(c, .lastDecisionId)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    private static func optionalUUID(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> UUID? {
        if let u = try? c.decodeIfPresent(UUID.self, forKey: key) { return u }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return UUID(uuidString: s) }
        return nil
    }
}

struct FullMission: Identifiable, Decodable, Equatable {
    let id: UUID
    var subjectId: UUID?
    var title: String
    var statement: String
    var situation: String
    var why: String
    var purpose: String
    var phase: MissionPhase
    var missionType: MissionKind
    var impactRating: String
    var stackSortOrder: Int
    var status: String
    var targets: [MissionTargetDetail]
    var state: MissionState?
    var completedTargetCount: Int
    var targetCount: Int

    enum CodingKeys: String, CodingKey {
        case id, title, statement, situation, why, purpose, phase, status, targets, state
        case subjectId = "subject_id"
        case missionType = "mission_type"
        case impactRating = "impact_rating"
        case stackSortOrder = "stack_sort_order"
        case completedTargetCount = "completed_target_count"
        case targetCount = "target_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let u = try? c.decode(UUID.self, forKey: .id) {
            id = u
        } else {
            let s = try c.decode(String.self, forKey: .id)
            id = UUID(uuidString: s) ?? UUID()
        }
        if let u = try? c.decodeIfPresent(UUID.self, forKey: .subjectId) {
            subjectId = u
        } else if let s = try c.decodeIfPresent(String.self, forKey: .subjectId) {
            subjectId = UUID(uuidString: s)
        } else {
            subjectId = nil
        }
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        statement = try c.decodeIfPresent(String.self, forKey: .statement) ?? title
        situation = try c.decodeIfPresent(String.self, forKey: .situation) ?? ""
        why = try c.decodeIfPresent(String.self, forKey: .why) ?? ""
        purpose = try c.decodeIfPresent(String.self, forKey: .purpose) ?? ""
        phase = try c.decodeIfPresent(MissionPhase.self, forKey: .phase) ?? .executing
        missionType = try c.decodeIfPresent(MissionKind.self, forKey: .missionType) ?? .supporting
        impactRating = try c.decodeIfPresent(String.self, forKey: .impactRating) ?? "medium"
        stackSortOrder = try c.decodeIfPresent(Int.self, forKey: .stackSortOrder) ?? 0
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "active"
        targets = try c.decodeIfPresent([MissionTargetDetail].self, forKey: .targets) ?? []
        state = try c.decodeIfPresent(MissionState.self, forKey: .state)
        completedTargetCount = try c.decodeIfPresent(Int.self, forKey: .completedTargetCount) ?? targets.filter { $0.status == .complete }.count
        targetCount = try c.decodeIfPresent(Int.self, forKey: .targetCount) ?? targets.count
    }

    var focusTarget: MissionTargetDetail? {
        targets.first(where: \.focusTarget) ?? targets.first(where: { $0.status != .complete })
    }

    var mustDo: [MissionTargetDetail] { targets.filter { $0.targetType == .essential } }
    var shouldDo: [MissionTargetDetail] { targets.filter { $0.targetType == .shouldHave } }
    var niceToDo: [MissionTargetDetail] { targets.filter { $0.targetType == .niceToHave } }
}

// MARK: - Stack

struct MissionStack: Decodable, Equatable {
    var primary: FullMission?
    var supporting: [FullMission]
    var dreams: [MissionDream]
    var primaryMissionId: UUID?

    enum CodingKeys: String, CodingKey {
        case primary, supporting, dreams
        case primaryMissionId = "primary_mission_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        primary = try c.decodeIfPresent(FullMission.self, forKey: .primary)
        supporting = try c.decodeIfPresent([FullMission].self, forKey: .supporting) ?? []
        dreams = try c.decodeIfPresent([MissionDream].self, forKey: .dreams) ?? []
        if let u = try? c.decodeIfPresent(UUID.self, forKey: .primaryMissionId) {
            primaryMissionId = u
        } else if let s = try c.decodeIfPresent(String.self, forKey: .primaryMissionId) {
            primaryMissionId = UUID(uuidString: s)
        } else {
            primaryMissionId = primary?.id
        }
    }

    init(primary: FullMission? = nil, supporting: [FullMission] = [], dreams: [MissionDream] = []) {
        self.primary = primary
        self.supporting = supporting
        self.dreams = dreams
        self.primaryMissionId = primary?.id
    }
}

// MARK: - Decisions & thoughts (Brain streams)

struct DecisionRecord: Identifiable, Decodable, Equatable {
    let id: UUID
    var missionId: UUID?
    var targetId: UUID?
    var title: String
    var context: String
    var options: [String]
    var chosen: String
    var humanSaid: String
    var aiRecommendation: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, context, options, chosen
        case missionId = "mission_id"
        case targetId = "target_id"
        case humanSaid = "human_said"
        case aiRecommendation = "ai_recommendation"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = Self.uuid(c, .id) ?? UUID()
        missionId = Self.uuid(c, .missionId)
        targetId = Self.uuid(c, .targetId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        context = try c.decodeIfPresent(String.self, forKey: .context) ?? ""
        if let opts = try? c.decode([String].self, forKey: .options) {
            options = opts
        } else {
            options = []
        }
        chosen = try c.decodeIfPresent(String.self, forKey: .chosen) ?? ""
        humanSaid = try c.decodeIfPresent(String.self, forKey: .humanSaid) ?? ""
        aiRecommendation = try c.decodeIfPresent(String.self, forKey: .aiRecommendation) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }

    private static func uuid(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> UUID? {
        if let u = try? c.decodeIfPresent(UUID.self, forKey: key) { return u }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return UUID(uuidString: s) }
        return nil
    }

    var isOpen: Bool {
        chosen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func asDecisionItem() -> DecisionItem {
        DecisionItem(
            id: id,
            title: title.isEmpty ? "Decision needed" : title,
            context: context,
            options: [
                DecisionOption(label: "Proceed", description: "Mark this decided and continue"),
                DecisionOption(label: "Adjust", description: "Open Chat about this"),
                DecisionOption(label: "Hold", description: "Keep this in Decisions needed for now"),
            ],
            generatedBy: "Your Sovereign",
            relatedMission: nil,
            urgency: .today,
            createdAt: Self.parseDate(createdAt) ?? .now,
            lifeDecisionId: id,
            kind: .life
        )
    }

    private static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let date = formatter.date(from: String(trimmed.prefix(19))) { return date }
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: String(trimmed.prefix(19)))
    }
}

struct ThoughtEntry: Identifiable, Decodable, Equatable {
    let id: UUID
    var missionId: UUID?
    var targetId: UUID?
    var activityType: String
    var summary: String
    var detail: String
    var progress: Double?
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, summary, detail, progress
        case missionId = "mission_id"
        case targetId = "target_id"
        case activityType = "activity_type"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let u = try? c.decode(UUID.self, forKey: .id) {
            id = u
        } else {
            let s = try c.decode(String.self, forKey: .id)
            id = UUID(uuidString: s) ?? UUID()
        }
        if let u = try? c.decodeIfPresent(UUID.self, forKey: .missionId) {
            missionId = u
        } else if let s = try c.decodeIfPresent(String.self, forKey: .missionId) {
            missionId = UUID(uuidString: s)
        } else {
            missionId = nil
        }
        if let u = try? c.decodeIfPresent(UUID.self, forKey: .targetId) {
            targetId = u
        } else if let s = try c.decodeIfPresent(String.self, forKey: .targetId) {
            targetId = UUID(uuidString: s)
        } else {
            targetId = nil
        }
        activityType = try c.decodeIfPresent(String.self, forKey: .activityType) ?? "thought"
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        progress = try c.decodeIfPresent(Double.self, forKey: .progress)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }
}

enum LifeJSON {
    static let snakeDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }()

    static func decode<T: Decodable>(_ type: T.Type, from object: Any) -> T? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            return nil
        }
        return try? snakeDecoder.decode(T.self, from: data)
    }
}
