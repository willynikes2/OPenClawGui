import SwiftUI

/// Elevation and shadow tokens.
/// Use sparingly — prefer separators and whitespace over heavy shadows.
enum Elevation {

    /// Subtle card shadow — primary elevation level
    static let card = ShadowStyle(
        color: Color.black.opacity(0.08),
        radius: 8,
        x: 0,
        y: 2
    )

    /// Slightly more prominent shadow for floating elements
    static let floating = ShadowStyle(
        color: Color.black.opacity(0.12),
        radius: 12,
        x: 0,
        y: 4
    )
}

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - View Modifier

struct ElevationModifier: ViewModifier {
    let style: ShadowStyle

    func body(content: Content) -> some View {
        content.shadow(
            color: style.color,
            radius: style.radius,
            x: style.x,
            y: style.y
        )
    }
}

extension View {
    func elevation(_ style: ShadowStyle) -> some View {
        modifier(ElevationModifier(style: style))
    }
}
