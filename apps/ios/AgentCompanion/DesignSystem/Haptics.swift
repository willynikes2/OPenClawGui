import UIKit

/// Haptic feedback aligned to the design system.
/// - success: light
/// - warning: medium
/// - destructive: heavy
/// Use sparingly — motion clarifies state, does not entertain.
enum Haptics {

    static func success() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    static func warning() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    static func destructive() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }

    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}
