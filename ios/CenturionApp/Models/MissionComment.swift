import Foundation

/// A comment on any mission level — program, target, or task.
/// Shows who wrote it and when, with full history preserved.
struct MissionComment: Identifiable, Codable, Equatable {
    let id: UUID
    let parentId: UUID
    let parentType: ParentType
    let text: String
    let author: Author
    let timestamp: Date
    
    enum ParentType: String, Codable {
        case program
        case target
        case task
    }
    
    enum Author: String, Codable {
        case human
        case centurion
        
        var displayName: String {
            switch self {
            case .human: return "You"
            case .centurion: return "Centurion"
            }
        }
    }
}
