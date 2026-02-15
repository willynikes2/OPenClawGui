import SwiftUI

// MARK: - Card Insertion Animation

/// Subtle entrance animation for cards appearing in lists.
/// Respects Reduce Motion: falls back to instant appearance.
struct CardInsertionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : (reduceMotion ? 0 : 8))
            .onAppear {
                guard !reduceMotion else {
                    isVisible = true
                    return
                }
                withAnimation(.easeOut(duration: 0.25)) {
                    isVisible = true
                }
            }
    }
}

// MARK: - Severity Badge Appearance

/// Scale + fade entrance for severity badges.
/// Respects Reduce Motion: shows immediately without scale.
struct SeverityBadgeAppearance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : (reduceMotion ? 1 : 0.8))
            .onAppear {
                guard !reduceMotion else {
                    isVisible = true
                    return
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isVisible = true
                }
            }
    }
}

// MARK: - View Extensions

extension View {
    /// Applies a subtle card insertion animation on appear.
    func cardInsertionAnimation() -> some View {
        modifier(CardInsertionModifier())
    }

    /// Applies a scale+fade appearance animation for badges.
    func badgeAppearanceAnimation() -> some View {
        modifier(SeverityBadgeAppearance())
    }
}
