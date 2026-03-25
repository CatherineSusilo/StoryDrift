import SwiftUI

/// Centralised design tokens — mirrors the web app's parchment/sepia theme.
/// All views should reference these instead of hard-coding colours.
enum Theme {

    // MARK: - Colours
    /// Warm parchment page background (#e4d5b7)
    static let background   = Color(red: 0.894, green: 0.835, blue: 0.718)
    /// Slightly lighter cream for cards / panels (#faf5eb ≈ rgba(250,245,235))
    static let card         = Color(red: 0.980, green: 0.961, blue: 0.922)
    /// Deep ink for primary text (rgba 20,15,10 at full opacity)
    static let ink          = Color(red: 0.078, green: 0.059, blue: 0.039)
    /// Muted ink for secondary / caption text
    static let inkMuted     = Color(red: 0.078, green: 0.059, blue: 0.039).opacity(0.60)
    /// Even lighter for placeholder / disabled
    static let inkFaint     = Color(red: 0.078, green: 0.059, blue: 0.039).opacity(0.35)
    /// Warm tan used for active tabs / button fills (rgba 210,180,140)
    static let accent       = Color(red: 0.824, green: 0.706, blue: 0.549)
    /// Card border (rgba 40,30,20 @ 0.25)
    static let border       = Color(red: 0.157, green: 0.118, blue: 0.078).opacity(0.25)
    /// Stronger border for active/selected states
    static let borderActive = Color(red: 0.157, green: 0.118, blue: 0.078).opacity(0.42)
    /// Destructive red
    static let destructive  = Color(red: 0.831, green: 0.094, blue: 0.239)
    /// Success green
    static let success      = Color(red: 0.275, green: 0.510, blue: 0.314)

    // MARK: - Gradients
    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.957, green: 0.910, blue: 0.816),
            Color(red: 0.894, green: 0.835, blue: 0.718),
            Color(red: 0.921, green: 0.871, blue: 0.796)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Shadows
    static let cardShadow = Color.black.opacity(0.09)

    // MARK: - Radius
    static let radiusSM: CGFloat = 6
    static let radiusMD: CGFloat = 10
    static let radiusLG: CGFloat = 14

    // MARK: - Typography helpers
    /// Large display / page title — Indie Flower handwritten style
    static func titleFont(size: CGFloat = 30) -> Font {
        .custom("IndieFlower-Regular", size: size)
    }
    /// Body / label — Patrick Hand handwritten style
    static func bodyFont(size: CGFloat = 16) -> Font {
        .custom("PatrickHand-Regular", size: size)
    }
}

// MARK: - View modifiers for convenience

extension View {
    /// Full-screen parchment background matching the web app
    func parchmentBackground() -> some View {
        self.background(Theme.background.ignoresSafeArea())
    }

    /// Standard card appearance: cream fill, subtle border, soft shadow
    func parchmentCard(cornerRadius: CGFloat = Theme.radiusMD) -> some View {
        self
            .background(Theme.card)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Theme.border, lineWidth: 1.5)
            )
            .shadow(color: Theme.cardShadow, radius: 4, x: 0, y: 2)
    }
}
