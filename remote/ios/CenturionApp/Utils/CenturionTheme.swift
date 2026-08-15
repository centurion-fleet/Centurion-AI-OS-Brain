import SwiftUI

/// Centurion v5 brand palette — warm paper & bronze, mapped from
/// `shared/design-tokens/tokens.json` (www.1human1ai.com, verified live Aug 2026).
///
/// Bronze is a spotlight, not wallpaper: avatar, active state, one primary CTA.
///
/// Usage:
///   `.background(ColorTheme.surface())`
///   `.foregroundColor(ColorTheme.accent())`

enum ColorTheme {

    // MARK: - Background

    /// Main page background — warm stone / warm near-black
    static func background() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.067, green: 0.047, blue: 0.035, alpha: 1.0)   // #110C09
                : UIColor(red: 0.980, green: 0.980, blue: 0.976, alpha: 1.0)   // #FAFAF9
        })
    }

    /// Phone frame / main view background
    static func phoneBackground() -> Color {
        background()
    }

    /// Panels, chrome, elevated stacks
    static func surface() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.102, green: 0.082, blue: 0.071, alpha: 1.0)   // #1A1512
                : UIColor(red: 0.953, green: 0.949, blue: 0.933, alpha: 1.0)   // #F3F2EE
        })
    }

    /// True cards / chat bubbles — white in light, same as surface in dark
    static func card() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.102, green: 0.082, blue: 0.071, alpha: 1.0)   // #1A1512
                : UIColor(white: 1.0, alpha: 1.0)                              // #FFFFFF
        })
    }

    // MARK: - Text

    /// Primary text — warm ink / warm cream
    static func primaryText() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.945, green: 0.933, blue: 0.906, alpha: 1.0)   // #F1EEE7
                : UIColor(red: 0.031, green: 0.020, blue: 0.012, alpha: 1.0)   // #080503
        })
    }

    // MARK: - Accent (one spotlight per screen)

    /// Bronze / pale bronze — tabs, PulseDot, primary CTA
    static func accent() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.827, green: 0.804, blue: 0.749, alpha: 1.0)   // #D3CDBF
                : UIColor(red: 0.263, green: 0.220, blue: 0.188, alpha: 1.0)   // #433830
        })
    }

    /// Text/icons sitting on `accent()` fills
    static func onAccent() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.067, green: 0.047, blue: 0.035, alpha: 1.0)   // #110C09
                : UIColor(red: 0.945, green: 0.933, blue: 0.906, alpha: 1.0)   // #F1EEE7
        })
    }

    /// Muted secondary chrome — same family as muted text
    static func dimAccent() -> Color {
        mutedText()
    }

    // MARK: - Functional (semantic, not decorative)

    static func success() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.290, green: 0.878, blue: 0.502, alpha: 1.0)   // #4ade80
                : UIColor(red: 0.180, green: 0.490, blue: 0.196, alpha: 1.0)   // #2e7d32
        })
    }

    static func error() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.937, green: 0.267, blue: 0.267, alpha: 1.0)   // #ef4444
                : UIColor(red: 0.906, green: 0.000, blue: 0.043, alpha: 1.0)   // #e7000b
        })
    }

    /// Caution / needs attention — muted amber (semantic)
    static func warning() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.984, green: 0.749, blue: 0.141, alpha: 1.0)   // #fbbf24
                : UIColor(red: 0.851, green: 0.580, blue: 0.020, alpha: 1.0)   // #d99405
        })
    }

    // MARK: - Chat specific

    static func chatInput() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.137, green: 0.118, blue: 0.106, alpha: 1.0)   // #231E1B
                : UIColor(red: 0.953, green: 0.949, blue: 0.933, alpha: 1.0)   // #F3F2EE
        })
    }

    static func userBubble() -> Color {
        card()
    }

    static func centurionBubble() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.102, green: 0.082, blue: 0.071, alpha: 0.85)  // #1A1512
                : UIColor(red: 0.263, green: 0.220, blue: 0.188, alpha: 0.06)  // bronze wash
        })
    }

    static func border() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.216, green: 0.196, blue: 0.180, alpha: 1.0)   // #37322E
                : UIColor(red: 0.855, green: 0.843, blue: 0.816, alpha: 1.0)   // #DAD7D0
        })
    }

    static func mutedText() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.588, green: 0.553, blue: 0.525, alpha: 1.0)   // #968D86
                : UIColor(red: 0.369, green: 0.325, blue: 0.290, alpha: 1.0)   // #5E534A
        })
    }

    // MARK: - Warm companions (aliases of bronze — not a second hue)

    static func amber() -> Color {
        accent()
    }

    static func agedBronze() -> Color {
        accent()
    }

    /// Legacy orb companion — paper surface, not teal
    static func atmosphereTeal() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.137, green: 0.118, blue: 0.106, alpha: 1.0)   // #231E1B
                : UIColor(red: 0.906, green: 0.894, blue: 0.867, alpha: 1.0)   // #E7E4DD
        })
    }

    static func pearlHighlight() -> Color {
        Color(red: 0.945, green: 0.933, blue: 0.906)   // #F1EEE7
    }

    static func surfaceElevated() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.137, green: 0.118, blue: 0.106, alpha: 1.0)   // #231E1B
                : UIColor(red: 0.953, green: 0.949, blue: 0.933, alpha: 1.0)   // #F3F2EE
        })
    }

    static func atmosphericVeil() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.827, green: 0.804, blue: 0.749, alpha: 0.04)
                : UIColor(red: 0.031, green: 0.020, blue: 0.012, alpha: 0.03)
        })
    }
}
