import SwiftUI

/// Always-visible affordance for Herald — Centurion's cloud support guide.
struct HeraldBar: View {
    @Binding var showHerald: Bool

    var body: some View {
        Button {
            Haptics.lightTap()
            showHerald = true
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "flag.fill")
                    .font(.subheadline.weight(.semibold))
                Text("Herald")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(ColorTheme.accent())
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.15), radius: 8, y: 4)
        }
        .accessibilityLabel("Open Herald support guide")
        .accessibilityHint("Talk to Centurion's cloud guide for help with this app")
    }
}
