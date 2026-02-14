import SwiftUI

/// Pill-shaped capsule badge with icon + text for severity levels.
/// Always pairs color with text and icon — never color-only.
struct SeverityBadge: View {
    let severity: Severity

    var body: some View {
        Label {
            Text(severity.label)
                .font(Typography.caption2)
                .fontWeight(.medium)
        } icon: {
            Image(systemName: severity.icon)
                .font(Typography.caption2)
        }
        .foregroundStyle(severity.color)
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .background(severity.color.opacity(0.12))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(severity.accessibilityLabel)
    }
}

#Preview {
    VStack(spacing: Space.sm) {
        SeverityBadge(severity: .info)
        SeverityBadge(severity: .warn)
        SeverityBadge(severity: .critical)
    }
    .padding()
}
