import SwiftUI

/// Opens the Sovereign help center in Safari.
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
        .accessibilityHint("Opens the Sovereign help website")
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
        .accessibilityHint("Open Adrian, Sovereign's creator online — caring expert guidance")
    }
}

extension Notification.Name {
    static let centurionSelectTab = Notification.Name("centurion.selectTab")
    /// Object is the `Conversation.id` to show on the Chat tab.
    static let centurionOpenConversation = Notification.Name("centurion.openConversation")
}

enum AdrianNavigation {
    static let chatTab = 0
    static let focusTab = 1
    static let collabTab = 2
    static let youTab = 3

    static func selectTab(_ index: Int) {
        NotificationCenter.default.post(name: .centurionSelectTab, object: index)
    }

    /// Switch to Chat and open a specific thread (Focus Adjust / Discuss).
    static func openChat(conversationId: UUID) {
        NotificationCenter.default.post(name: .centurionOpenConversation, object: conversationId)
        selectTab(chatTab)
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
            selectTab(youTab)
        case .openMission:
            showAdrian.wrappedValue = false
            selectTab(focusTab)
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
