import Foundation

/// Client-canonical Discuss framing for Collab / Document / Decision / Horizon.
/// Mirrors Desktop `chat_page.rs` shapes so Brain receives the same topic context.
enum TopicDiscussChat {
    static func frameCollab(
        userText: String,
        name: String,
        boardId: String?
    ) -> String {
        let boardLine: String
        if let boardId, !boardId.isEmpty {
            boardLine = "Collaboration board: \(boardId)\n"
        } else {
            boardLine = ""
        }
        return """
        [Sovereign AI Brain — Collaboration discuss]
        \(boardLine)Name: \(name)

        Help the user with this local collaboration. Prefer kanban_* tools when the board is available. \
        Keep other missions out of this thread unless the user brings them in.

        User message:
        \(userText)
        """
    }

    static func frameDocument(
        userText: String,
        title: String,
        documentId: String?,
        missionId: String?
    ) -> String {
        var meta = "Document: \(title)\n"
        if let documentId, !documentId.isEmpty {
            meta += "Document ID: \(documentId)\n"
        }
        if let missionId, !missionId.isEmpty {
            meta += "Mission ID: \(missionId)\n"
        }
        return """
        [Sovereign AI Brain — Document discuss]
        \(meta)
        Discuss and refine this document. Prefer life_missions document tools when ids are present. \
        Do not invent storage the user does not have.

        User message:
        \(userText)
        """
    }

    static func frameDecision(userText: String, title: String) -> String {
        """
        [Sovereign AI Brain — Decision discuss]
        Decision: \(title)

        Help the user reason about this choice and next steps. Prefer clarify when options are unclear.

        User message:
        \(userText)
        """
    }

    static func frameHorizon(userText: String, layer: String) -> String {
        """
        [Sovereign AI Brain — Memory Horizon discuss]
        Layer: \(layer)

        Help the user understand and manage this memory layer. Do not invent storage they do not have.

        User message:
        \(userText)
        """
    }

    /// Optional `life_inject` payload for Mission / Document / Decision Discuss.
    static func lifeInject(
        userText: String,
        context: ConversationContext
    ) -> [String: Any]? {
        switch context {
        case .mission(let id, _, _):
            return [
                "message": userText,
                "current_view": [
                    "mission_id": id.uuidString,
                ],
            ]
        case .missionTarget(let targetId, _, let missionId, _, _):
            return [
                "message": userText,
                "current_view": [
                    "mission_id": missionId.uuidString,
                    "target_id": targetId.uuidString,
                ],
            ]
        case .document(let id, _, let missionId):
            var inject: [String: Any] = ["message": userText]
            var view: [String: Any] = [:]
            if let missionId {
                view["mission_id"] = missionId.uuidString
            }
            if !view.isEmpty {
                inject["current_view"] = view
            }
            if let id {
                inject["document_ids"] = [id.uuidString]
            }
            return inject
        case .decision:
            return ["message": userText]
        case .commitment(let id, _):
            return [
                "message": userText,
                "current_view": [
                    "target_id": id.uuidString,
                ],
            ]
        default:
            return nil
        }
    }
}
