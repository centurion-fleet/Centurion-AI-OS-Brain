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
    case standalone(title: String)

    var displayTitle: String {
        switch self {
        case .program(_, let name): return name
        case .target(_, let name, _): return name
        case .task(_, let name, _, _): return name
        case .commitment(_, let title): return title
        case .plan(_, let title): return title
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

    /// Coding keys — flattened for Codable conformance
    enum CodingKeys: String, CodingKey {
        case type, id, name, programName, targetName, title
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
        case lan      // Local network (mDNS) — fallback only
        case tailscale // Tailscale mesh — preferred path

        var icon: String {
            switch self {
            case .lan: return "wifi"
            case .tailscale: return "shield.fill"
            }
        }

        /// Short badge for Device link UI.
        var linkBadge: String {
            switch self {
            case .lan: return "Wi‑Fi"
            case .tailscale: return "Tailscale"
            }
        }
    }

    /// True when this device should be reached over Tailscale first.
    var isTailscalePath: Bool {
        connectionMethod == .tailscale
            || Self.isTailscaleEndpoint(hostname: hostname, ipAddress: ipAddress)
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

    var displayTitle: String { context.displayTitle }
    var contextPath: String { context.contextPath }
    var icon: String { context.icon }
    var missionBadge: (name: String, color: Color) { context.missionBadge }
}

extension ConversationContext {
    var isStandalone: Bool {
        if case .standalone = self { return true }
        return false
    }
}
