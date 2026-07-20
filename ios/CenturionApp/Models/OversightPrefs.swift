import Foundation

/// Autonomy ladder — maps to host ``agent.autonomy_level``.
enum AutonomyLevel: String, CaseIterable, Identifiable, Codable {
    case strict
    case balanced
    case proactive
    case high

    var id: String { rawValue }

    var label: String {
        switch self {
        case .strict: return "Strict"
        case .balanced: return "Balanced"
        case .proactive: return "Proactive"
        case .high: return "High Autonomy"
        }
    }

    var detail: String {
        switch self {
        case .strict:
            return "Follow instructions exactly, minimal initiative."
        case .balanced:
            return "Follow instructions with light interpretation."
        case .proactive:
            return "Can suggest improvements and take small actions."
        case .high:
            return "Maximum freedom within defined boundaries."
        }
    }

    static var `default`: AutonomyLevel { .balanced }
}

/// How often the Centurion reports back — host ``oversight.report_cadence``.
enum ReportCadence: String, CaseIterable, Identifiable, Codable {
    case off
    case whenNeeded = "when_needed"
    case daily
    case afterSignificantActions = "after_significant_actions"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .whenNeeded: return "When needed"
        case .daily: return "Daily"
        case .afterSignificantActions: return "After significant actions"
        }
    }

    var detail: String {
        switch self {
        case .off:
            return "Stay quiet unless you ask."
        case .whenNeeded:
            return "Report when a choice is needed, something fails, or a milestone completes."
        case .daily:
            return "Prefer a concise daily-style status when progress accumulates."
        case .afterSignificantActions:
            return "Briefly report after each significant action."
        }
    }

    static var `default`: ReportCadence { .whenNeeded }
}

/// Host-backed autonomy + reporting preferences (cached locally for offline display).
struct OversightPrefs: Codable, Equatable {
    var autonomyLevel: AutonomyLevel
    var reportCadence: ReportCadence
    var askBeforeInitiative: Bool
    var confirmDangerousCommands: Bool
    var confirmExternalActions: Bool
    var approvalsMode: String
    var syncedWithSovereign: Bool

    static var `default`: OversightPrefs {
        OversightPrefs(
            autonomyLevel: .balanced,
            reportCadence: .whenNeeded,
            askBeforeInitiative: true,
            confirmDangerousCommands: true,
            confirmExternalActions: true,
            approvalsMode: "manual",
            syncedWithSovereign: false
        )
    }

    static func fromHostPayload(_ payload: [String: Any]) -> OversightPrefs {
        var prefs = OversightPrefs.default
        if let level = payload["autonomy_level"] as? String,
           let parsed = AutonomyLevel(rawValue: level) {
            prefs.autonomyLevel = parsed
        }
        if let cadence = payload["report_cadence"] as? String,
           let parsed = ReportCadence(rawValue: cadence) {
            prefs.reportCadence = parsed
        }
        if let ask = payload["ask_before_initiative"] as? Bool {
            prefs.askBeforeInitiative = ask
        }
        if let dangerous = payload["confirm_dangerous_commands"] as? Bool {
            prefs.confirmDangerousCommands = dangerous
        }
        if let external = payload["confirm_external_actions"] as? Bool {
            prefs.confirmExternalActions = external
        }
        if let mode = payload["approvals_mode"] as? String {
            prefs.approvalsMode = mode
        }
        prefs.syncedWithSovereign = true
        return prefs
    }

    func toHostPayload() -> [String: Any] {
        [
            "autonomy_level": autonomyLevel.rawValue,
            "report_cadence": reportCadence.rawValue,
            "ask_before_initiative": askBeforeInitiative,
            "confirm_dangerous_commands": confirmDangerousCommands,
            "confirm_external_actions": confirmExternalActions,
        ]
    }
}
