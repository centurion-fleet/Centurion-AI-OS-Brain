import Foundation

/// Framing and parsing for Living Commitment chats on Centurion Remote.
enum MissionCommitmentChat {
    static let updateFence = "mission-update"

    struct UpdatePayload: Decodable {
        let commitment_id: String
        let title: String?
        let description: String?
        let active: Bool?
    }

    static func frameOutbound(
        userText: String,
        commitment: LifeMissionTarget,
        mission: LifeMission
    ) -> String {
        let statement = mission.statement.trimmingCharacters(in: .whitespacesAndNewlines)
        let missionLine = statement.isEmpty
            ? "(not set yet)"
            : statement
        return """
        [Centurion Remote — Living Commitment chat]
        Life mission: \(missionLine)
        Commitment: \(commitment.title)
        Description: \(commitment.description)
        Commitment ID: \(commitment.id.uuidString)

        The user is discussing or revising this living commitment. You may suggest renames, \
        clearer descriptions, or deactivating it. If you apply a change the user agrees to, \
        end your reply with a fenced block exactly like this (omit fields you are not changing):

        ```\(updateFence)
        {"commitment_id":"\(commitment.id.uuidString)","title":"New title","description":"New description","active":true}
        ```

        User message:
        \(userText)
        """
    }

    static func parseUpdate(from response: String) -> UpdatePayload? {
        guard let block = extractUpdateBlock(from: response),
              let data = block.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(UpdatePayload.self, from: data)
    }

    static func displayText(strippingUpdateBlockFrom response: String) -> String {
        let open = "```\(updateFence)"
        guard let start = response.range(of: open) else {
            return response.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var result = String(response[..<start.lowerBound])
        if let closeStart = response.range(of: "```", range: start.upperBound..<response.endIndex) {
            result += String(response[closeStart.upperBound...])
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractUpdateBlock(from response: String) -> String? {
        let open = "```\(updateFence)"
        guard let start = response.range(of: open) else { return nil }
        let afterOpen = response[start.upperBound...]
        guard let close = afterOpen.range(of: "```") else { return nil }
        return String(afterOpen[..<close.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
