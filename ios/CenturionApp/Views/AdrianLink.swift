import SwiftUI

/// Inline entry for Adrian — matches Get Help link weight on Connect and You.
struct AdrianLink: View {
    @Binding var showAdrian: Bool

    var body: some View {
        Button {
            Haptics.lightTap()
            showAdrian = true
        } label: {
            Text("Talk to Adrian")
                .font(.subheadline.weight(.medium))
                .foregroundColor(ColorTheme.accent())
        }
        .accessibilityLabel("Talk to Adrian")
        .accessibilityHint("Open Centurion's cloud support guide")
    }
}

extension Notification.Name {
    static let centurionSelectTab = Notification.Name("centurion.selectTab")
}

enum AdrianNavigation {
    static func selectTab(_ index: Int) {
        NotificationCenter.default.post(name: .centurionSelectTab, object: index)
    }

    @MainActor
    static func handleAction(
        _ action: AdrianAction,
        showAdrian: Binding<Bool>,
        showGetHelp: Binding<Bool>? = nil,
        connectionManager: ConnectionManager
    ) {
        switch action {
        case .openConnect:
            showAdrian.wrappedValue = false
            selectTab(0)
        case .openMission:
            showAdrian.wrappedValue = false
            selectTab(2)
        case .openGetHelp:
            showAdrian.wrappedValue = false
            showGetHelp?.wrappedValue = true
        case .tryAutoFix:
            Task {
                _ = await connectionManager.autoFixThinking()
                await connectionManager.refreshThinkingStatus()
            }
        }
    }
}
