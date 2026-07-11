import Foundation
import SwiftUI

/// Tracks whether the app is showing sample data vs live Centurion data.
@MainActor
final class AppDataMode: ObservableObject {
    @Published private(set) var showsDemoContent: Bool = true

    func update(connectionState: ConnectionManager.ConnectionState) {
        showsDemoContent = connectionState != .connected
    }
}
