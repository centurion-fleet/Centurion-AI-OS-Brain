import SwiftUI

/// Legacy list switcher — replaced by ``ThinkingServiceDialView``.
/// Kept as a thin redirect so any stale navigation links still open the dial.
struct RemoteModelSwitcherView: View {
    var body: some View {
        ThinkingServiceDialView()
    }
}
