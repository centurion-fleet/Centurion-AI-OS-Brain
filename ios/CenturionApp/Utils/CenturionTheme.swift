import SwiftUI

/// Centurion brand colour palette — light and dark variants.
/// All colours automatically adapt to the user's system appearance setting.
///
/// Usage:
///   `.background(ColorTheme.surface())`
///   `.foregroundColor(ColorTheme.accent())`
///   `ColorTheme.amber`
///
/// These respect the system's light/dark mode automatically via traitCollections.

enum ColorTheme {
    
    // MARK: - Background
    
    /// Main page background behind the app chrome
    static func background() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.016, green: 0.110, blue: 0.110, alpha: 1.0)   // #041c1c
                : UIColor(red: 0.961, green: 0.941, blue: 0.910, alpha: 1.0)   // #f5f0e8
        })
    }
    
    /// Phone frame / main view background
    static func phoneBackground() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.016, green: 0.110, blue: 0.110, alpha: 1.0)   // #041c1c
                : UIColor(red: 0.980, green: 0.965, blue: 0.937, alpha: 1.0)   // #faf6ef
        })
    }
    
    /// Card, chat bubble, container surfaces
    static func surface() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.039, green: 0.165, blue: 0.165, alpha: 1.0)   // #0a2a2a
                : UIColor(white: 1.0, alpha: 1.0)                              // #ffffff
        })
    }
    
    // MARK: - Text
    
    /// Primary text (cream in dark, deep brown in light)
    static func primaryText() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 1.0, green: 0.902, blue: 0.796, alpha: 1.0)     // #ffe6cb
                : UIColor(red: 0.176, green: 0.165, blue: 0.141, alpha: 1.0)   // #2d2a24
        })
    }
    
    // MARK: - Accent
    
    /// Primary accent — amber gold (dark) / Centurion blue (light)
    static func accent() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 1.0, green: 0.843, blue: 0.0, alpha: 1.0)       // #ffd700
                : UIColor(red: 0.145, green: 0.388, blue: 0.922, alpha: 1.0)   // #2563eb
        })
    }
    
    /// Muted / dim accent for secondary elements
    static func dimAccent() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.722, green: 0.588, blue: 0.239, alpha: 1.0)   // #b8963d
                : UIColor(red: 0.376, green: 0.647, blue: 0.980, alpha: 1.0)   // #60a5fa
        })
    }
    
    // MARK: - Functional
    
    /// Success green (connected, delivered)
    static func success() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.290, green: 0.878, blue: 0.502, alpha: 1.0)   // #4ade80
                : UIColor(red: 0.180, green: 0.490, blue: 0.196, alpha: 1.0)   // #2e7d32
        })
    }
    
    /// Error red (disconnected, error)
    static func error() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.937, green: 0.267, blue: 0.267, alpha: 1.0)   // #ef4444
                : UIColor(red: 0.776, green: 0.157, blue: 0.157, alpha: 1.0)   // #c62828
        })
    }
    
    // MARK: - Chat specific
    
    /// Chat input field background
    static func chatInput() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.039, green: 0.165, blue: 0.165, alpha: 1.0)   // #0a2a2a
                : UIColor(red: 0.941, green: 0.922, blue: 0.886, alpha: 1.0)   // #f0ebe2
        })
    }
    
    /// User's own message bubble
    static func userBubble() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.039, green: 0.165, blue: 0.165, alpha: 1.0)   // #0a2a2a
                : UIColor(white: 1.0, alpha: 1.0)                              // #ffffff
        })
    }
    
    /// Centurion's message bubble
    static func centurionBubble() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.039, green: 0.165, blue: 0.165, alpha: 0.6)   // rgba(10,42,42,0.6)
                : UIColor(red: 0.145, green: 0.388, blue: 0.922, alpha: 0.05)  // rgba(37,99,235,0.05)
        })
    }
    
    /// Subtle border colour
    static func border() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 1.0, green: 0.902, blue: 0.796, alpha: 0.12)    // rgba(255,230,203,0.12)
                : UIColor(red: 0.176, green: 0.165, blue: 0.141, alpha: 0.10)  // rgba(45,42,36,0.10)
        })
    }
    
    /// Secondary / muted text
    static func mutedText() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 1.0, green: 0.902, blue: 0.796, alpha: 0.50)    // rgba(255,230,203,0.5)
                : UIColor(red: 0.176, green: 0.165, blue: 0.141, alpha: 0.45)  // rgba(45,42,36,0.45)
        })
    }

    // MARK: - Brand ramp (Art Deco / atmospheric)

    /// Warm amber gold — brand primary in dark, accent companion in light
    static func amber() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 1.0, green: 0.843, blue: 0.0, alpha: 1.0)
                : UIColor(red: 0.722, green: 0.478, blue: 0.212, alpha: 1.0)   // #b87a36
        })
    }

    static func agedBronze() -> Color {
        Color(red: 0.55, green: 0.42, blue: 0.28)
    }

    static func atmosphereTeal() -> Color {
        Color(red: 0.22, green: 0.58, blue: 0.56)
    }

    static func pearlHighlight() -> Color {
        Color(red: 1.0, green: 0.96, blue: 0.88)
    }

    /// Elevated hero / modal surfaces
    static func surfaceElevated() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.055, green: 0.20, blue: 0.20, alpha: 1.0)
                : UIColor(red: 1.0, green: 0.99, blue: 0.97, alpha: 1.0)
        })
    }

    /// Atmospheric vignette tint over backgrounds
    static func atmosphericVeil() -> Color {
        Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.22, green: 0.58, blue: 0.56, alpha: 0.06)
                : UIColor(red: 0.722, green: 0.478, blue: 0.212, alpha: 0.04)
        })
    }
}
