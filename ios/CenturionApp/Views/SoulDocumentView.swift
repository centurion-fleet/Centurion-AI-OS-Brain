import SwiftUI

/// Your Centurion's Soul — how your AI companion speaks and behaves.
struct SoulDocumentView: View {
    @EnvironmentObject private var missionStore: MissionStore
    @State private var showShareSheet = false
    @State private var showInterview = false

    private var soul: SoulDocument { missionStore.soul }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                FullBrandHeader()

                soulHero

                if soul.isValid {
                    soulContent

                    Button(action: {
                        Haptics.mediumTap()
                        showInterview = true
                    }) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "pencil")
                                .font(.subheadline)
                            Text("Shape Your Centurion")
                        }
                    }
                    .buttonStyle(CenturionSecondaryButtonStyle())
                    .padding(.bottom, Spacing.lg)
                } else {
                    emptyState
                        .padding(.bottom, Spacing.lg)
                }
            }
            .frame(maxWidth: 428)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(secondaryBackground)
        .navigationTitle("Your Centurion's Soul")
        .toolbar {
            if soul.isValid {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        Haptics.lightTap()
                        showShareSheet = true
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.accent())
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            shareSheet
        }
        .sheet(isPresented: $showInterview) {
            SoulInterviewView(existingSoul: missionStore.soul) { document in
                missionStore.updateSoul(document)
            }
        }
    }

    private var secondaryBackground: some View {
        ZStack {
            ColorTheme.background()
            ColorTheme.atmosphericVeil()
                .ignoresSafeArea()
        }
    }

    // MARK: - Hero

    private var soulHero: some View {
        AtmosphericSurface(elevated: true, showRim: true) {
            VStack(spacing: Spacing.md) {
                CenturionSectionHeader(title: "Personality", icon: "sparkles")

                Text("Your Centurion's Soul")
                    .font(Typography.editorialTitle)
                    .foregroundColor(ColorTheme.primaryText())
                    .multilineTextAlignment(.center)

                Text("How your companion speaks and behaves")
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.mutedText())
                    .multilineTextAlignment(.center)

                if !soul.personalitySummary.isEmpty {
                    Text(soul.personalitySummary)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.dimAccent())
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.top, Spacing.xs)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyState: some View {
        EmptyState(
            icon: "sparkles",
            title: "Not set yet",
            message: "Define how it speaks, what it always does, and what it never does. This is separate from your life mission — it's about your AI companion.",
            actionTitle: "Set Up Your Centurion's Soul",
            action: {
                Haptics.mediumTap()
                showInterview = true
            }
        )
    }

    private var soulContent: some View {
        VStack(spacing: Spacing.md) {
            if !soul.tone.isEmpty {
                sectionCard(icon: "waveform", title: "Tone", content: soul.tone)
            }
            if !soul.communicationStyle.isEmpty {
                sectionCard(icon: "bubble.left.and.bubble.right", title: "How It Speaks", content: soul.communicationStyle)
            }
            if !soul.responseLength.isEmpty {
                sectionCard(icon: "text.alignleft", title: "Response Length", content: soul.responseLength)
            }
            if !soul.pushbackStyle.isEmpty {
                sectionCard(icon: "hand.raised", title: "When It Pushes Back", content: soul.pushbackStyle)
            }
            if !soul.uncertaintyStyle.isEmpty {
                sectionCard(icon: "questionmark.circle", title: "Handling Uncertainty", content: soul.uncertaintyStyle)
            }
            if !soul.alwaysDo.isEmpty {
                sectionCard(icon: "checkmark.circle", title: "Always Does", tags: soul.alwaysDo)
            }
            if !soul.neverDo.isEmpty {
                sectionCard(icon: "xmark.circle", title: "Never Does", tags: soul.neverDo)
            }

            VStack(spacing: Spacing.xs) {
                Rectangle()
                    .fill(ColorTheme.accent().opacity(0.2))
                    .frame(width: 40, height: 1)
                Text("Updated \(formatDate(soul.updatedAt))")
                    .font(.caption2)
                    .foregroundColor(ColorTheme.mutedText())
            }
            .padding(.top, Spacing.sm)
        }
    }

    private func sectionCard(icon: String, title: String, content: String? = nil, tags: [String]? = nil) -> some View {
        AtmosphericSurface {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                CenturionSectionHeader(title: title, icon: icon)

                if let content = content, !content.isEmpty {
                    Text(content)
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.mutedText())
                        .lineSpacing(4)
                }

                if let tags = tags, !tags.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(ColorTheme.accent())
                                    .frame(width: 4, height: 4)
                                Text(tag)
                                    .font(.caption)
                                    .foregroundColor(ColorTheme.primaryText())
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Share

    private var shareSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    SheetHeader(title: "Your Centurion's Soul")

                    AtmosphericSurface(elevated: true) {
                        VStack(spacing: Spacing.md) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 36))
                                .foregroundColor(ColorTheme.accent())

                            if !soul.personalitySummary.isEmpty {
                                Text(soul.personalitySummary)
                                    .font(.subheadline)
                                    .foregroundColor(ColorTheme.primaryText())
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(4)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    Text("Share how your Centurion is configured to work with you.")
                        .font(.caption)
                        .foregroundColor(ColorTheme.mutedText())
                        .multilineTextAlignment(.center)

                    Button(action: {
                        Haptics.mediumTap()
                        UIPasteboard.general.string = generateShareText()
                    }) {
                        Label("Copy to Clipboard", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(CenturionSecondaryButtonStyle())

                    Button(action: {
                        Haptics.mediumTap()
                        let text = generateShareText()
                        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let root = windowScene.windows.first?.rootViewController {
                            root.present(activityVC, animated: true)
                        }
                    }) {
                        Label("Share...", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(CenturionGhostButtonStyle())
                }
                .padding()
            }
            .background(ColorTheme.background())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showShareSheet = false }
                        .foregroundColor(ColorTheme.accent())
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func generateShareText() -> String {
        var text = "✨ Your Centurion's Soul — Centurion AI\n\n"
        if !soul.personalitySummary.isEmpty {
            text += "\(soul.personalitySummary)\n\n"
        }
        if !soul.tone.isEmpty { text += "Tone: \(soul.tone)\n" }
        if !soul.communicationStyle.isEmpty { text += "Speaks: \(soul.communicationStyle)\n" }
        if !soul.alwaysDo.isEmpty { text += "Always: \(soul.alwaysDo.joined(separator: ", "))\n" }
        if !soul.neverDo.isEmpty { text += "Never: \(soul.neverDo.joined(separator: ", "))\n" }
        text += "\nHow my Centurion is configured to work with me."
        return text
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
}
