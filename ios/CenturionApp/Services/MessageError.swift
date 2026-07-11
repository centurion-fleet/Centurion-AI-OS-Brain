import Foundation

enum MessageError: Error, LocalizedError {
    case notConnected

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Connect to your Centurion in the Connect tab before sending messages."
        }
    }
}
