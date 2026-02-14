import SwiftUI

/// Semantic color tokens.
/// All colors use system semantics — no hardcoded hex values.
/// Dark mode is automatic via system color usage.
enum AppColors {

    // MARK: - Severity (semantic, not hardcoded)

    static let severityInfo = Color.blue
    static let severityWarn = Color.orange
    static let severityCritical = Color.red

    // MARK: - Health Status

    static let healthOK = Color.green
    static let healthDegraded = Color.orange
    static let healthOffline = Color.red

    // MARK: - Trust Status

    static let trusted = Color.green
    static let untrusted = Color.red
    static let unknown = Color.gray

    // MARK: - Backgrounds

    /// Card background using system grouped background
    static let cardBackground = Color(.secondarySystemGroupedBackground)

    /// Subtle tint for critical items
    static let criticalTint = Color.red.opacity(0.08)

    /// Unread indicator dot
    static let unreadDot = Color.blue
}
