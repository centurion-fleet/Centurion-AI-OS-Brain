import SwiftUI

/// Signum — the palette and type scale for the chat surface.
///
/// Why a second theme file exists: the app's existing `ColorTheme` is the deep
/// forest/ivory shell built for the five-tab dashboard. Signum is the opposite
/// proposition — one screen, quiet, printed rather than lit — and it uses the
/// live website's palette (cream ground, ink text, one gold), because a customer
/// who has read 1association1ai.com should recognise the product in their hand.
///
/// ⚠️ Do not "harmonise" this back into `ColorTheme`. The two themes are two
/// products. If the dashboard returns, it keeps its own.
enum SignumTheme {

    // MARK: - Ground

    static let cream = dynamic(light: 0xFAF9F6, dark: 0x121009)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x1B1811)
    static let ink = dynamic(light: 0x141109, dark: 0xF4F1E9)
    static let muted = dynamic(light: 0x7C766A, dark: 0x9E9788)

    /// The one accent. Slightly lifted in dark mode so it does not disappear
    /// into the ground — same hue, same job.
    static let gold = dynamic(light: 0xB8A06A, dark: 0xC9B27C)
    static let goldDeep = dynamic(light: 0x8E7742, dark: 0xD3BF8E)

    static let hair = dynamic(light: 0x141109, dark: 0xF4F1E9).opacity(0.10)
    static let hairStrong = dynamic(light: 0x141109, dark: 0xF4F1E9).opacity(0.18)

    // MARK: - Type

    /// The Centurion's voice — headlines, the empty state, the name in the header.
    /// New York (system serif) rather than a bundled face: zero assets, zero
    /// Info.plist font registration, and it renders identically on every device.
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// The interface. Everything the customer taps or reads as body copy.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Machine labels only: the working line, timestamps, section marks.
    /// Never for prose — mono prose is a costume.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Metrics

    enum Metrics {
        static let screenPadding: CGFloat = 20
        static let messageSpacing: CGFloat = 18
        static let headerHeight: CGFloat = 52
        static let composerRadius: CGFloat = 24
        static let bubbleRadius: CGFloat = 20
    }

    // MARK: - Helpers

    /// A colour that adapts without needing an asset catalogue entry, so this
    /// file stays self-contained and cannot be broken by a missing asset.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
