import SwiftUI

/// Opens the Personal Centurion help center in Safari.
struct HelpCenterLink: View {
    var title: String = "Browse Help Center"
    var url: URL = CenturionHelp.baseURL

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            Haptics.lightTap()
            openURL(url)
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(ColorTheme.accent())
        }
        .accessibilityLabel(title)
        .accessibilityHint("Opens the Personal Centurion help website")
    }
}

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
        .accessibilityHint("Open Adrian, Centurion's creator online — caring expert guidance")
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
            selectTab(2)
        case .openMission:
            showAdrian.wrappedValue = false
            selectTab(1)
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
