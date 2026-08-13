import SwiftUI

/// Review a Sovereign-proposed Plan before Proceed / Adjust / Hold.
/// Pattern mirrors Mission Discovery synthesis review — calm, editable feel, clear actions.
struct PlanReviewView: View {
    let plan: PlanArtifact
    var onProceed: () -> Void
    var onAdjust: () -> Void
    var onHold: () -> Void
    /// Always-available Discuss — reopens the plan-scoped Crypto Chat thread.
    var onDiscuss: (() -> Void)? = nil
    var onShare: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var reviewerId = ""
    @State private var shareMessage: String?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header

                    if !plan.goal.isEmpty {
                        section(title: "Goal", icon: "target") {
                            Text(plan.goal)
                                .font(.body)
                                .foregroundColor(ColorTheme.primaryText())
                                .lineSpacing(4)
                        }
                    }

                    if !plan.steps.isEmpty {
                        section(title: "Proposed steps", icon: "list.number") {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                                    HStack(alignment: .top, spacing: Spacing.sm) {
                                        Text("\(index + 1).")
                                            .font(.subheadline.weight(.bold))
                                            .foregroundColor(ColorTheme.accent())
                                            .frame(width: 24, alignment: .leading)
                                        Text(step)
                                            .font(.subheadline)
                                            .foregroundColor(ColorTheme.primaryText())
                                            .lineSpacing(3)
                                    }
                                }
                            }
                        }
                    }

                    if !plan.risks.isEmpty {
                        section(title: "Risks", icon: "exclamationmark.triangle") {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                ForEach(plan.risks, id: \.self) { risk in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("•")
                                            .foregroundColor(ColorTheme.accent())
                                        Text(risk)
                                            .font(.subheadline)
                                            .foregroundColor(ColorTheme.mutedText())
                                            .lineSpacing(3)
                                    }
                                }
                            }
                        }
                    }

                    if !plan.openQuestions.isEmpty {
                        section(title: "Open questions", icon: "questionmark.circle") {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                ForEach(plan.openQuestions, id: \.self) { question in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("•")
                                            .foregroundColor(ColorTheme.accent())
                                        Text(question)
                                            .font(.subheadline)
                                            .foregroundColor(ColorTheme.mutedText())
                                            .lineSpacing(3)
                                    }
                                }
                            }
                        }
                    }

                    if !plan.summary.isEmpty {
                        section(title: "Summary", icon: "text.alignleft") {
                            Text(plan.summary)
                                .font(.subheadline)
                                .foregroundColor(ColorTheme.mutedText())
                                .lineSpacing(4)
                        }
                    }

                    if !plan.share.reviewers.isEmpty || !plan.share.comments.isEmpty {
                        section(title: "Shared review", icon: "person.2") {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                ForEach(plan.share.reviewers) { reviewer in
                                    Text("\(reviewer.customerId) — \(reviewer.status)")
                                        .font(.caption)
                                        .foregroundColor(ColorTheme.mutedText())
                                }
                                ForEach(plan.share.comments) { comment in
                                    Text("\(comment.author): \(comment.body)")
                                        .font(.caption)
                                        .foregroundColor(ColorTheme.primaryText())
                                }
                            }
                        }
                    }

                    if onShare != nil {
                        section(title: "Share for review", icon: "square.and.arrow.up") {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                TextField("Reviewer customer id", text: $reviewerId)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(.subheadline)
                                Button {
                                    let trimmed = reviewerId.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    Haptics.mediumTap()
                                    onShare?(trimmed)
                                    shareMessage = "Shared for review."
                                } label: {
                                    Text("Share with reviewer")
                                }
                                .buttonStyle(CenturionSecondaryButtonStyle())
                                if let shareMessage {
                                    Text(shareMessage)
                                        .font(.caption)
                                        .foregroundColor(ColorTheme.mutedText())
                                }
                            }
                        }
                    }

                    VStack(spacing: Spacing.sm) {
                        Button {
                            Haptics.success()
                            onProceed()
                            dismiss()
                        } label: {
                            Text("Proceed")
                        }
                        .buttonStyle(CenturionPrimaryButtonStyle())

                        Button {
                            Haptics.mediumTap()
                            onAdjust()
                            dismiss()
                        } label: {
                            Text("Adjust")
                        }
                        .buttonStyle(CenturionSecondaryButtonStyle())

                        Button {
                            Haptics.lightTap()
                            onHold()
                            dismiss()
                        } label: {
                            Text("Hold")
                        }
                        .buttonStyle(CenturionGhostButtonStyle())
                    }
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, onDiscuss == nil ? 0 : 72)
                }
                .frame(maxWidth: 428)
                .padding()
                .frame(maxWidth: .infinity)
            }

            if onDiscuss != nil {
                discussBubble
                    .padding(.trailing, Spacing.lg)
                    .padding(.bottom, Spacing.lg)
            }
        }
        .background(
            ZStack {
                ColorTheme.background()
                ColorTheme.atmosphericVeil()
                    .ignoresSafeArea()
            }
        )
        .navigationTitle("Review this plan")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var discussBubble: some View {
        Button {
            Haptics.lightTap()
            onDiscuss?()
            dismiss()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.body.weight(.semibold))
                Text("Discuss")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(ColorTheme.accent())
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Discuss this plan")
        .accessibilityHint("Opens Crypto Chat about this plan. You can return anytime.")
    }

    private var header: some View {
        AtmosphericSurface(elevated: true) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: 6) {
                    Image(systemName: "list.clipboard")
                        .font(.caption.weight(.semibold))
                    Text("PLAN")
                        .font(Typography.sectionLabel)
                        .tracking(1.5)
                    if let risk = plan.risk {
                        Spacer()
                        Text(risk.displayLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(ColorTheme.accent())
                    }
                }
                .foregroundColor(ColorTheme.accent())

                Text("Your Sovereign proposes…")
                    .font(.caption)
                    .foregroundColor(ColorTheme.mutedText())

                Text(plan.title)
                    .font(Typography.editorialTitle)
                    .foregroundColor(ColorTheme.primaryText())
                    .lineSpacing(4)

                Text(plan.status.displayLabel)
                    .font(.caption.weight(.medium))
                    .foregroundColor(ColorTheme.dimAccent())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            CenturionSectionHeader(title: title, icon: icon)
            AtmosphericSurface {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
