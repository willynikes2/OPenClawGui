import SwiftUI

/// Corner radius tokens.
enum Radii {
    /// 16pt — cards, panels
    static let card: CGFloat = 16
    /// Capsule shape — pills, badges
    static let pill: CGFloat = 999
    /// 12pt — buttons
    static let button: CGFloat = 12
    // Sheets use system default (no custom radius)
}
