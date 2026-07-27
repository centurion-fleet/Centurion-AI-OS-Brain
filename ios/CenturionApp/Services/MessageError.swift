import Foundation

enum MessageError: Error, LocalizedError {
    case notConnected
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Connect to your Sovereign in You before sending messages."
        case .emptyResponse:
            return "Your Sovereign got the message but sent no reply. Open You → Thinking Service and run Check / Auto-fix, then try again."
        }
    }
}
