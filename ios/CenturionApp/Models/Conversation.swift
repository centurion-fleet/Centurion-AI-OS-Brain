import Foundation
import SwiftUI

/// Wrapper for sheet(item:) presentation — avoids timing issues with separate
/// chatContext + showChat state vars.
struct ChatSheetTarget: Identifiable {
    let id = UUID()
    let context: ConversationContext
}

/// Where in the mission hierarchy a conversation lives.
/// Every chat is attached to a mission element — or standalone.
enum ConversationContext: Codable, Equatable, Hashable {
    case program(id: UUID, name: String)
    case target(id: UUID, name: String, programName: String)
    case task(id: UUID, name: String, targetName: String, programName: String)
    /// A living commitment from the user's life mission (Mission → Active Commitments).
    case commitment(id: UUID, title: String)
    /// A reviewable Plan from Home — same thread reopens anytime via Discuss.
    case plan(id: UUID, title: String)
    /// Full Mission hierarchy (Subject → Mission → Target) from Brain life.db.
    case mission(id: UUID, name: String, subjectName: String?)
    case missionTarget(
        id: UUID,
        name: String,
        missionId: UUID,
        missionName: String,
        subjectName: String?
    )
    /// Local collaboration board Discuss (Brain kanban swarm).
    case collab(id: UUID, name: String, boardId: String?)
    /// Focus / Documents Discuss.
    case document(id: UUID?, title: String, missionId: UUID?)
    /// Decision Discuss from Home / Focus.
    case decision(id: UUID, title: String)
    /// Memory Horizon layer Discuss.
    case horizon(layer: String)
    case standalone(title: String)

    var displayTitle: String {
        switch self {
        case .program(_, let name): return name
        case .target(_, let name, _): return name
        case .task(_, let name, _, _): return name
        case .commitment(_, let title): return title
        case .plan(_, let title): return title
        case .mission(_, let name, _): return name
        case .missionTarget(_, let name, _, _, _): return name
        case .collab(_, let name, _): return name
        case .document(_, let title, _): return title
        case .decision(_, let title): return title
        case .horizon(let layer): return "Memory Horizon · \(layer)"
        case .standalone(let title): return title
        }
    }

    var contextPath: String {
        switch self {
        case .program(_, let name): return name
        case .target(_, let name, let program): return "\(program) > \(name)"
        case .task(_, let name, let target, let program): return "\(program) > \(target) > \(name)"
        case .commitment(_, let title): return "Commitment · \(title)"
        case .plan(_, let title): return "Plan · \(title)"
        case .mission(_, let name, let subject):
            if let subject, !subject.isEmpty { return "\(subject) > \(name)" }
            return "Mission · \(name)"
        case .missionTarget(_, let name, _, let mission, let subject):
            if let subject, !subject.isEmpty { return "\(subject) > \(mission) > \(name)" }
            return "\(mission) > \(name)"
        case .collab(_, let name, _): return "Collaboration · \(name)"
        case .document(_, let title, _): return "Document · \(title)"
        case .decision(_, let title): return "Decision · \(title)"
        case .horizon(let layer): return "Memory Horizon · \(layer)"
        case .standalone: return "Chat"
        }
    }

    var icon: String {
        switch self {
        case .program: return "target"
        case .target: return "arrow.triangle.branch"
        case .task: return "checkmark.circle"
        case .commitment: return "target"
        case .plan: return "list.clipboard"
        case .mission: return "flag.fill"
        case .missionTarget: return "checkmark.circle.fill"
        case .collab: return "person.3.fill"
        case .document: return "doc.text.fill"
        case .decision: return "arrow.triangle.branch"
        case .horizon: return "circle.hexagongrid.fill"
        case .standalone: return "message.fill"
        }
    }

    /// The leading mission-level badge shown on each message in the global stream
    var missionBadge: (name: String, color: Color) {
        switch self {
        case .program(_, let name):
            return (name, ColorTheme.accent())
        case .target(_, let name, let program):
            return ("\(program) > \(name)", ColorTheme.accent().opacity(0.8))
        case .task(_, let name, let target, let program):
            return ("\(program) > \(target) > \(name)", ColorTheme.dimAccent())
        case .commitment(_, let title):
            return ("Commitment · \(title)", ColorTheme.accent())
        case .plan(_, let title):
            return ("Plan · \(title)", ColorTheme.accent())
        case .mission(_, let name, let subject):
            let label = subject.map { "\($0) · \(name)" } ?? name
            return (label, ColorTheme.accent())
        case .missionTarget(_, let name, _, let mission, _):
            return ("\(mission) > \(name)", ColorTheme.accent().opacity(0.85))
        case .collab(_, let name, _):
            return ("Collab · \(name)", ColorTheme.accent())
        case .document(_, let title, _):
            return ("Document · \(title)", ColorTheme.accent().opacity(0.9))
        case .decision(_, let title):
            return ("Decision · \(title)", ColorTheme.accent())
        case .horizon(let layer):
            return ("Horizon · \(layer)", ColorTheme.accent().opacity(0.85))
        case .standalone:
            return ("Chat", ColorTheme.mutedText())
        }
    }

    var commitmentID: UUID? {
        if case .commitment(let id, _) = self { return id }
        return nil
    }

    var planID: UUID? {
        if case .plan(let id, _) = self { return id }
        return nil
    }

    var missionID: UUID? {
        switch self {
        case .mission(let id, _, _): return id
        case .missionTarget(_, _, let missionId, _, _): return missionId
        case .document(_, _, let missionId): return missionId
        default: return nil
        }
    }

    var missionTargetID: UUID? {
        if case .missionTarget(let id, _, _, _, _) = self { return id }
        return nil
    }

    /// Brain SessionDB topic_kind for durable Discuss restore.
    var hostTopicKind: String? {
        switch self {
        case .plan: return "plan"
        case .commitment: return "commitment"
        case .mission, .missionTarget: return "mission"
        case .collab: return "collab"
        case .document: return "document"
        case .decision: return "decision"
        case .horizon: return "horizon"
        case .standalone: return "generic"
        case .program, .target, .task: return "generic"
        }
    }

    /// Brain SessionDB topic_ref JSON object.
    var hostTopicRef: [String: Any]? {
        switch self {
        case .plan(let id, let title):
            return ["plan_id": id.uuidString, "title": title]
        case .commitment(let id, let title):
            return ["commitment_id": id.uuidString, "title": title]
        case .mission(let id, let name, let subjectName):
            var ref: [String: Any] = ["mission_id": id.uuidString, "title": name]
            if let subjectName { ref["subject_name"] = subjectName }
            return ref
        case .missionTarget(let id, let name, let missionId, let missionName, _):
            return [
                "mission_id": missionId.uuidString,
                "target_id": id.uuidString,
                "target_title": name,
                "title": missionName,
            ]
        case .collab(let id, let name, let boardId):
            return [
                "id": id.uuidString,
                "name": name,
                "board_id": boardId ?? id.uuidString,
            ]
        case .document(let id, let title, let missionId):
            var ref: [String: Any] = ["title": title]
            if let id { ref["id"] = id.uuidString }
            if let missionId { ref["mission_id"] = missionId.uuidString }
            return ref
        case .decision(let id, let title):
            return ["decision_id": id.uuidString, "title": title]
        case .horizon(let layer):
            return ["layer": layer]
        case .standalone(let title):
            return ["title": title, "kind": "topic"]
        case .program(_, let name), .target(_, let name, _), .task(_, let name, _, _):
            return ["title": name, "kind": "topic"]
        }
    }

    /// Coding keys — flattened for Codable conformance
    enum CodingKeys: String, CodingKey {
        case type, id, name, programName, targetName, title, subjectName, missionName, missionId, boardId, layer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "program":
            let id = try container.decode(UUID.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            self = .program(id: id, name: name)
        case "target":
            let id = try container.decode(UUID.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let programName = try container.decode(String.self, forKey: .programName)
            self = .target(id: id, name: name, programName: programName)
        case "task":
            let id = try container.decode(UUID.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let targetName = try container.decode(String.self, forKey: .targetName)
            let programName = try container.decode(String.self, forKey: .programName)
            self = .task(id: id, name: name, targetName: targetName, programName: programName)
        case "commitment":
            let id = try container.decode(UUID.self, forKey: .id)
            let title = try container.decode(String.self, forKey: .title)
            self = .commitment(id: id, title: title)
        case "plan":
            let id = try container.decode(UUID.self, forKey: .id)
            let title = try container.decode(String.self, forKey: .title)
            self = .plan(id: id, title: title)
        case "mission":
            let id = try container.decode(UUID.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let subjectName = try container.decodeIfPresent(String.self, forKey: .subjectName)
            self = .mission(id: id, name: name, subjectName: subjectName)
        case "missionTarget":
            let id = try container.decode(UUID.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let missionName = try container.decode(String.self, forKey: .missionName)
            let subjectName = try container.decodeIfPresent(String.self, forKey: .subjectName)
            let missionId = try container.decodeIfPresent(UUID.self, forKey: .missionId)
                ?? UUID()
            self = .missionTarget(
                id: id,
                name: name,
                missionId: missionId,
                missionName: missionName,
                subjectName: subjectName
            )
        case "collab":
            let id = try container.decode(UUID.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let boardId = try container.decodeIfPresent(String.self, forKey: .boardId)
            self = .collab(id: id, name: name, boardId: boardId)
        case "document":
            let id = try container.decodeIfPresent(UUID.self, forKey: .id)
            let title = try container.decode(String.self, forKey: .title)
            let missionId = try container.decodeIfPresent(UUID.self, forKey: .missionId)
            self = .document(id: id, title: title, missionId: missionId)
        case "decision":
            let id = try container.decode(UUID.self, forKey: .id)
            let title = try container.decode(String.self, forKey: .title)
            self = .decision(id: id, title: title)
        case "horizon":
            let layer = try container.decode(String.self, forKey: .layer)
            self = .horizon(layer: layer)
        case "standalone":
            let title = try container.decode(String.self, forKey: .title)
            self = .standalone(title: title)
        default:
            self = .standalone(title: "Chat")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .program(let id, let name):
            try container.encode("program", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
        case .target(let id, let name, let programName):
            try container.encode("target", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(programName, forKey: .programName)
        case .task(let id, let name, let targetName, let programName):
            try container.encode("task", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(targetName, forKey: .targetName)
            try container.encode(programName, forKey: .programName)
        case .commitment(let id, let title):
            try container.encode("commitment", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(title, forKey: .title)
        case .plan(let id, let title):
            try container.encode("plan", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(title, forKey: .title)
        case .mission(let id, let name, let subjectName):
            try container.encode("mission", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(subjectName, forKey: .subjectName)
        case .missionTarget(let id, let name, let missionId, let missionName, let subjectName):
            try container.encode("missionTarget", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(missionId, forKey: .missionId)
            try container.encode(missionName, forKey: .missionName)
            try container.encodeIfPresent(subjectName, forKey: .subjectName)
        case .collab(let id, let name, let boardId):
            try container.encode("collab", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(boardId, forKey: .boardId)
        case .document(let id, let title, let missionId):
            try container.encode("document", forKey: .type)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encode(title, forKey: .title)
            try container.encodeIfPresent(missionId, forKey: .missionId)
        case .decision(let id, let title):
            try container.encode("decision", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(title, forKey: .title)
        case .horizon(let layer):
            try container.encode("horizon", forKey: .type)
            try container.encode(layer, forKey: .layer)
        case .standalone(let title):
            try container.encode("standalone", forKey: .type)
            try container.encode(title, forKey: .title)
        }
    }
}

/// A Sovereign device discovered on the local network via Bonjour.
struct CenturionDevice: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let hostname: String
    let ipAddress: String
    let port: Int
    let serviceName: String?
    let serviceType: String?
    let serviceDomain: String?
    let publicKey: Data?
    let isConnected: Bool
    let connectionMethod: ConnectionMethod
    let lastSeen: Date

    init(
        id: UUID,
        name: String,
        hostname: String,
        ipAddress: String,
        port: Int,
        serviceName: String? = nil,
        serviceType: String? = nil,
        serviceDomain: String? = nil,
        publicKey: Data?,
        isConnected: Bool,
        connectionMethod: ConnectionMethod,
        lastSeen: Date
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.ipAddress = ipAddress
        self.port = port
        self.serviceName = serviceName
        self.serviceType = serviceType
        self.serviceDomain = serviceDomain
        self.publicKey = publicKey
        self.isConnected = isConnected
        self.connectionMethod = connectionMethod
        self.lastSeen = lastSeen
    }

    enum CodingKeys: String, CodingKey {
        case id, name, hostname, ipAddress, port
        case serviceName, serviceType, serviceDomain
        case publicKey, isConnected, connectionMethod, lastSeen
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        hostname = try container.decode(String.self, forKey: .hostname)
        ipAddress = try container.decode(String.self, forKey: .ipAddress)
        port = try container.decode(Int.self, forKey: .port)
        serviceName = try container.decodeIfPresent(String.self, forKey: .serviceName)
        serviceType = try container.decodeIfPresent(String.self, forKey: .serviceType)
        serviceDomain = try container.decodeIfPresent(String.self, forKey: .serviceDomain)
        publicKey = try container.decodeIfPresent(Data.self, forKey: .publicKey)
        isConnected = try container.decode(Bool.self, forKey: .isConnected)
        lastSeen = try container.decode(Date.self, forKey: .lastSeen)
        if let method = try container.decodeIfPresent(ConnectionMethod.self, forKey: .connectionMethod) {
            connectionMethod = method
        } else {
            connectionMethod = Self.isTailscaleEndpoint(hostname: hostname, ipAddress: ipAddress)
                ? .tailscale
                : .lan
        }
    }

    enum ConnectionMethod: String, Codable {
        case lan      // Local network (mDNS) — same-network bonus
        case remote   // Authenticated remote pairing — primary path
        case tailscale // Tailscale mesh — optional legacy

        var icon: String {
            switch self {
            case .lan: return "wifi"
            case .remote: return "network"
            case .tailscale: return "shield.fill"
            }
        }

        /// Short badge for Device link UI.
        var linkBadge: String {
            switch self {
            case .lan: return "Wi‑Fi"
            case .remote: return "Remote"
            case .tailscale: return "Tailscale"
            }
        }
    }

    /// True when this device should be reached over Tailscale.
    var isTailscalePath: Bool {
        connectionMethod == .tailscale
            || Self.isTailscaleEndpoint(hostname: hostname, ipAddress: ipAddress)
    }

    /// True when this device was linked via remote pairing token.
    var isRemotePath: Bool {
        connectionMethod == .remote
    }

    static func isTailscaleEndpoint(hostname: String, ipAddress: String) -> Bool {
        isTailscaleHost(hostname) || isTailscaleHost(ipAddress)
    }

    static func isTailscaleHost(_ value: String) -> Bool {
        let host = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !host.isEmpty else { return false }
        if host.contains("ts.net") || host.contains("tailscale") { return true }
        // Tailscale CGNAT range 100.64.0.0/10
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4, parts[0] == 100, (64...127).contains(parts[1]) {
            return true
        }
        return false
    }

    func asConnected(
        publicKey: Data?,
        hostname: String? = nil,
        port: Int? = nil,
        ipAddress: String? = nil,
        connectionMethod: ConnectionMethod? = nil
    ) -> CenturionDevice {
        let resolvedHostname = hostname ?? self.hostname
        let resolvedIP = ipAddress ?? self.ipAddress
        let resolvedMethod = connectionMethod
            ?? (Self.isTailscaleEndpoint(hostname: resolvedHostname, ipAddress: resolvedIP)
                ? .tailscale
                : self.connectionMethod)
        return CenturionDevice(
            id: id,
            name: name,
            hostname: resolvedHostname,
            ipAddress: resolvedIP,
            port: port ?? (self.port > 0 ? self.port : 9119),
            serviceName: serviceName,
            serviceType: serviceType,
            serviceDomain: serviceDomain,
            publicKey: publicKey,
            isConnected: true,
            connectionMethod: resolvedMethod,
            lastSeen: Date()
        )
    }
}

/// A conversation thread — always tied to a mission context.
/// The gold grouping unit in the app.
struct Conversation: Identifiable, Codable, Equatable {
    let id: UUID
    var context: ConversationContext
    var lastActive: Date
    /// Set only by offline sample seeding — never inferred from titles
    /// (live Crypto Chat can reuse the same names).
    var isDemoSeed: Bool
    /// Host SessionDB id when linked to the Sovereign (durable multi-session).
    var hostSessionId: String?

    var displayTitle: String { context.displayTitle }
    var contextPath: String { context.contextPath }
    var icon: String { context.icon }
    var missionBadge: (name: String, color: Color) { context.missionBadge }

    init(
        id: UUID,
        context: ConversationContext,
        lastActive: Date,
        isDemoSeed: Bool = false,
        hostSessionId: String? = nil
    ) {
        self.id = id
        self.context = context
        self.lastActive = lastActive
        self.isDemoSeed = isDemoSeed
        self.hostSessionId = hostSessionId
    }

    enum CodingKeys: String, CodingKey {
        case id, context, lastActive, isDemoSeed, hostSessionId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        context = try container.decode(ConversationContext.self, forKey: .context)
        lastActive = try container.decode(Date.self, forKey: .lastActive)
        isDemoSeed = try container.decodeIfPresent(Bool.self, forKey: .isDemoSeed) ?? false
        hostSessionId = try container.decodeIfPresent(String.self, forKey: .hostSessionId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(context, forKey: .context)
        try container.encode(lastActive, forKey: .lastActive)
        try container.encode(isDemoSeed, forKey: .isDemoSeed)
        try container.encodeIfPresent(hostSessionId, forKey: .hostSessionId)
    }

    /// Titles used by historical offline samples (pre-`isDemoSeed` field).
    /// Only applied when the demo-session flag is still set — never for live chats.
    static let legacyDemoTitleMarkers: Set<String> = [
        "Morning Briefing",
        "Pipeline Review",
        "Q3 Go-to-Market",
        "Partner Onboarding",
        "Design visual assets",
    ]

    var matchesLegacyDemoTitle: Bool {
        Self.legacyDemoTitleMarkers.contains(displayTitle)
    }
}

extension ConversationContext {
    var isStandalone: Bool {
        if case .standalone = self { return true }
        return false
    }
}
