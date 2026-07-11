import SwiftUI

/// The Soul Document — a beautiful, shareable portrait of who the human is.
/// This is what they show other people. It should feel like a leather-bound
/// journal entry, not a form.
struct SoulDocumentView: View {
    @EnvironmentObject private var missionStore: MissionStore
    @State private var showShareSheet = false
    @State private var showInterview = false
    @State private var showEditHint = false

    private var soul: SoulDocument { missionStore.soul }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Cover page
                coverPage

                // Who You Are
                if !soul.yourStory.isEmpty {
                    sectionCard(
                        icon: "person.fill",
                        title: "My Story",
                        content: soul.yourStory
                    )
                }

                // Values
                if !soul.yourValues.isEmpty {
                    sectionCard(
                        icon: "heart.fill",
                        title: "My Values",
                        tags: soul.yourValues
                    )
                }

                // Mission
                if !soul.missionStatement.isEmpty {
                    VStack(spacing: Spacing.sm) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "target")
                                .font(.caption)
                                .foregroundColor(ColorTheme.accent())
                            Text("My Mission")
                                .font(.headline)
                                .foregroundColor(ColorTheme.primaryText())
                            Spacer()
                        }

                        Text(soul.missionStatement)
                            .font(.system(size: 20, weight: .bold, design: .serif))
                            .foregroundColor(ColorTheme.accent())
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity)

                        if !soul.whyThisMission.isEmpty {
                            Text(soul.whyThisMission)
                                .font(.subheadline)
                                .foregroundColor(ColorTheme.mutedText())
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding()
                    .cardStyle()
                }

                // How I Work
                if !soul.workStyle.isEmpty || !soul.communicationStyle.isEmpty {
                    sectionCard(
                        icon: "bolt.fill",
                        title: "How I Work",
                        content: [soul.workStyle, soul.communicationStyle]
                            .filter { !$0.isEmpty }
                            .joined(separator: "\n\n")
                    )
                }

                // Goals
                if !soul.goals.isEmpty {
                    sectionCard(
                        icon: "star.fill",
                        title: "My Goals",
                        tags: soul.goals
                    )
                }

                // Delegate Preferences
                if !soul.delegatePreferences.isEmpty {
                    sectionCard(
                        icon: "hand.raised.fill",
                        title: "What I Want Help With",
                        tags: soul.delegatePreferences
                    )
                }

                // Key People
                if !soul.keyRelationships.isEmpty {
                    sectionCard(
                        icon: "person.2.fill",
                        title: "My People",
                        tags: soul.keyRelationships
                    )
                }

                // Footer
                VStack(spacing: 8) {
                    Rectangle()
                        .fill(ColorTheme.accent().opacity(0.2))
                        .frame(width: 40, height: 1)

                    Text("Created \(formatDate(soul.createdAt))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(ColorTheme.mutedText())

                    Text("Updated \(formatDate(soul.updatedAt))")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(ColorTheme.mutedText())
                }
                .padding(.bottom, Spacing.lg)

                // Edit button
                Button(action: {
                    Haptics.mediumTap()
                    showInterview = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                        Text("Edit My Soul")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(ColorTheme.accent())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(ColorTheme.accent().opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 428)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("My Soul")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    Haptics.lightTap()
                    showShareSheet = true
                }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                        .foregroundColor(ColorTheme.accent())
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            shareSheet
        }
        .sheet(isPresented: $showInterview) {
            SoulInterviewView(existingSoul: missionStore.soul) { document in
                missionStore.completeDiscovery(with: document)
            }
        }
    }

    // MARK: - Cover Page

    private var coverPage: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 48))
                .foregroundColor(ColorTheme.accent())

            Text("SOUL")
                .font(.system(size: 32, weight: .bold, design: .serif))
                .foregroundColor(ColorTheme.primaryText())
                .tracking(8)

            if !soul.missionStatement.isEmpty {
                Text(soul.missionStatement)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.dimAccent())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, Spacing.xl)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section Card

    private func sectionCard(icon: String, title: String, content: String? = nil, tags: [String]? = nil) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(ColorTheme.accent())
                Text(title)
                    .font(.headline)
                    .foregroundColor(ColorTheme.primaryText())
                Spacer()
            }

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
                                .font(.system(size: 12))
                                .foregroundColor(ColorTheme.primaryText())
                        }
                    }
                }
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Share Sheet

    private var shareSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Preview card
                VStack(spacing: 16) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 36))
                        .foregroundColor(ColorTheme.accent())

                    Text("SOUL")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .tracking(6)

                    Text(soul.missionStatement)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)

                    if !soul.yourValues.isEmpty {
                        Text(soul.yourValues.prefix(3).joined(separator: "  •  "))
                            .font(.caption)
                            .foregroundColor(ColorTheme.dimAccent())
                    }
                }
                .foregroundColor(ColorTheme.primaryText())
                .padding()
                .frame(maxWidth: .infinity)
                .cardStyle()

                Text("Share your Soul document with someone you trust.\nIt shows them who you are and what you're building.")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())
                    .multilineTextAlignment(.center)

                Button(action: {
                    Haptics.mediumTap()
                    let text = generateShareText()
                    UIPasteboard.general.string = text
                }) {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.accent())
                }
                .buttonStyle(.plain)
                .padding()
                .background(ColorTheme.accent().opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

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
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.accent())
                }
                .buttonStyle(.plain)
            }
            .padding()
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
        var text = "🤍 MY SOUL — Centurion AI\n\n"
        text += "\"\(soul.missionStatement)\"\n\n"
        if !soul.yourValues.isEmpty {
            text += "Values: \(soul.yourValues.joined(separator: ", "))\n\n"
        }
        if !soul.goals.isEmpty {
            text += "Goals: \(soul.goals.joined(separator: ", "))\n"
        }
        text += "\nBuilt with Centurion AI — Live Your Personal Mission"
        return text
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
}
