import Foundation
import SwiftUI

/// Tracks whether the app is showing sample data vs live Centurion data.
/// Release builds never seed a fake life — unpaired users see an empty state.
@MainActor
final class AppDataMode: ObservableObject {
    #if DEBUG
    @Published private(set) var showsDemoContent: Bool = true
    #else
    @Published private(set) var showsDemoContent: Bool = false
    #endif

    func update(isCryptoChatReady: Bool) {
        #if DEBUG
        showsDemoContent = !isCryptoChatReady
        #else
        showsDemoContent = false
        #endif
    }
}
