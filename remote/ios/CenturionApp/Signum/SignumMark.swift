import SwiftUI

/// The Signum mark — the standard on the pole, in the app's one accent colour.
///
/// Drawn rather than shipped as an asset: one path, no @2x/@3x, no dark-mode
/// variant, and it stays crisp at 16pt in a header or 200pt in an empty state.
/// A rendered image would need four files and would still look soft on the small
/// size.
struct SignumMark: View {
    var size: CGFloat = 30
    /// Fill strength of the star. The header star is a watermark, the empty
    /// state can carry more.
    var starOpacity: Double = 0.28

    var body: some View {
        ZStack {
            Circle()
                .stroke(SignumTheme.gold, lineWidth: max(1, size * 0.038))

            StarShape()
                .fill(SignumTheme.gold.opacity(starOpacity))
                .overlay(
                    StarShape().stroke(SignumTheme.goldDeep, lineWidth: max(0.8, size * 0.030))
                )
                .padding(size * 0.20)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A five-pointed star inscribed in the unit rect — the standard a century carried.
private struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.42
        let points = 5

        for i in 0..<(points * 2) {
            let radius = i.isMultiple(of: 2) ? outer : inner
            let angle = (Double(i) * .pi / Double(points)) - .pi / 2
            let point = CGPoint(
                x: centre.x + CGFloat(cos(angle)) * radius,
                y: centre.y + CGFloat(sin(angle)) * radius
            )
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack(spacing: 24) {
        SignumMark(size: 34)
        SignumMark(size: 120, starOpacity: 0.18)
    }
    .padding(40)
    .background(SignumTheme.cream)
}
