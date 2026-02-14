import SwiftUI

/// Event and alert severity levels.
enum Severity: String, Codable, CaseIterable, Identifiable {
    case info
    case warn
    case critical

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .info: "Info"
        case .warn: "Warning"
        case .critical: "Critical"
        }
    }

    var icon: String {
        switch self {
        case .info: "info.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .info: AppColors.severityInfo
        case .warn: AppColors.severityWarn
        case .critical: AppColors.severityCritical
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .info: String(localized: "Info")
        case .warn: String(localized: "Warning")
        case .critical: String(localized: "Critical alert")
        }
    }
}
