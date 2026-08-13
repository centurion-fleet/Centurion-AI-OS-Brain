import SwiftUI

/// Centurion v5 brand palette — mapped from `shared/shared/design-tokens/tokens.json`
/// (sales site `app/globals.css`). Light is cream/near-ink; dark is a derived
/// near-black family (not forest/teal). Interactive blue is for chrome/links
/// only; marketing CTAs on web use near-ink primary.
///
/// Usage:
///   `.background(ColorTheme.surface())`
///   `.foregroundColor(ColorTheme.accent())`

enum ColorTheme {

    // MARK: - Background

    /// Main page background behind the app chrome — v5 cream / derived dark ink
    static func background() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.047, green: 0.039, blue: 0.031, alpha: 1.0)   // #0c0a08
                : UIColor(red: 0.980, green: 0.980, blue: 0.976, alpha: 1.0)   // #fafaf9
        })
    }

    /// Phone frame / main view background
    static func phoneBackground() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.047, green: 0.039, blue: 0.031, alpha: 1.0)   // #0c0a08
                : UIColor(red: 0.980, green: 0.980, blue: 0.976, alpha: 1.0)   // #fafaf9
        })
    }

    /// Card, chat bubble, container surfaces
    static func surface() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.102, green: 0.090, blue: 0.078, alpha: 1.0)   // #1a1714
                : UIColor(white: 1.0, alpha: 1.0)                              // #ffffff
        })
    }

    // MARK: - Text

    /// Primary text — near-ink light / cream dark
    static func primaryText() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.980, green: 0.980, blue: 0.976, alpha: 1.0)   // #fafaf9
                : UIColor(red: 0.102, green: 0.086, blue: 0.071, alpha: 1.0)   // #1a1612
        })
    }

    // MARK: - Accent (interactive chrome)

    /// Interactive accent — cool blue (tabs, links). Not forest/gold.
    static func accent() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.376, green: 0.647, blue: 0.980, alpha: 1.0)   // #60a5fa
                : UIColor(red: 0.145, green: 0.388, blue: 0.922, alpha: 1.0)   // #2563eb
        })
    }

    /// Muted / dim accent for secondary elements
    static func dimAccent() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.576, green: 0.773, blue: 0.992, alpha: 1.0)   // #93c5fd
                : UIColor(red: 0.376, green: 0.647, blue: 0.980, alpha: 1.0)   // #60a5fa
        })
    }

    // MARK: - Functional

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

    /// Caution / needs attention — amber (e.g. linked but thinking unhealthy).
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
                ? UIColor(red: 0.165, green: 0.145, blue: 0.125, alpha: 1.0)   // #2a2520
                : UIColor(red: 0.953, green: 0.949, blue: 0.933, alpha: 1.0)   // #f3f2ee
        })
    }

    static func userBubble() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.102, green: 0.090, blue: 0.078, alpha: 1.0)   // #1a1714
                : UIColor(white: 1.0, alpha: 1.0)
        })
    }

    static func centurionBubble() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.102, green: 0.090, blue: 0.078, alpha: 0.85)
                : UIColor(red: 0.145, green: 0.388, blue: 0.922, alpha: 0.05)
        })
    }

    static func border() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.227, green: 0.204, blue: 0.173, alpha: 1.0)   // #3a342c
                : UIColor(red: 0.855, green: 0.843, blue: 0.816, alpha: 1.0)   // #dad7d0
        })
    }

    static func mutedText() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.639, green: 0.604, blue: 0.557, alpha: 1.0)   // #a39a8e
                : UIColor(red: 0.369, green: 0.325, blue: 0.290, alpha: 1.0)   // #5e534a
        })
    }

    // MARK: - Warm companions (sparing — not primary chrome)

    static func amber() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.843, green: 0.659, blue: 0.408, alpha: 1.0)   // #d7a868
                : UIColor(red: 0.722, green: 0.478, blue: 0.212, alpha: 1.0)   // #b87a36
        })
    }

    static func agedBronze() -> Color {
        Color(red: 0.55, green: 0.42, blue: 0.28)
    }

    /// Kept for legacy sphere/orb call sites; prefer muted cream surfaces.
    static func atmosphereTeal() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.184, green: 0.165, blue: 0.141, alpha: 1.0)   // accentSurface dark
                : UIColor(red: 0.906, green: 0.894, blue: 0.867, alpha: 1.0)   // #e7e4dd
        })
    }

    static func pearlHighlight() -> Color {
        Color(red: 0.980, green: 0.980, blue: 0.976)
    }

    static func surfaceElevated() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.133, green: 0.118, blue: 0.102, alpha: 1.0)   // #221e1a
                : UIColor(red: 0.953, green: 0.949, blue: 0.933, alpha: 1.0)   // #f3f2ee
        })
    }

    static func atmosphericVeil() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.145, green: 0.388, blue: 0.922, alpha: 0.04)
                : UIColor(red: 0.102, green: 0.086, blue: 0.071, alpha: 0.03)
        })
    }
}
