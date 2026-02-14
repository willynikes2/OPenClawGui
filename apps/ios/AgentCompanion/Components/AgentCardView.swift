import SwiftUI

/// Universal card component for events, alerts, and status blocks.
///
/// Structure per spec:
/// - Leading icon (SF Symbol)
/// - Title (1–2 lines)
/// - Subtitle (1–3 lines)
/// - Optional chips row (skill, agent, severity)
/// - Trailing relative time
///
/// States: normal, unread (bold title + dot), critical (tinted background + badge)
struct AgentCardView: View {
    let icon: String
    let title: String
    let subtitle: String
    let severity: Severity
    let timestamp: Date
    var skillName: String? = nil
    var agentName: String? = nil
    var isUnread: Bool = false
    var tags: [String]? = nil

    private var isCritical: Bool { severity == .critical }

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            // Leading icon
            Image(systemName: icon)
                .font(Typography.headline)
                .foregroundStyle(severity.color)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.xs) {
                // Title row with unread dot
                HStack(spacing: Space.xs) {
                    if isUnread {
                        Circle()
                            .fill(AppColors.unreadDot)
                            .frame(width: 8, height: 8)
                            .accessibilityLabel(String(localized: "Unread"))
                    }

                    Text(title)
                        .font(Typography.headline)
                        .fontWeight(isUnread ? .bold : .semibold)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                }

                // Subtitle
                Text(subtitle)
                    .font(Typography.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                // Chips row
                chipsRow
            }

            Spacer(minLength: 0)

            // Trailing time
            VStack(alignment: .trailing, spacing: Space.xs) {
                Text(timestamp, style: .relative)
                    .font(Typography.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                if isCritical {
                    SeverityBadge(severity: .critical)
                }
            }
        }
        .cardStyle(isCritical: isCritical)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(.isButton)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var chipsRow: some View {
        let chips = buildChips()
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xs) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip)
                            .font(Typography.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Space.sm)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }

                    if !isCritical {
                        SeverityBadge(severity: severity)
                    }
                }
            }
        }
    }

    private func buildChips() -> [String] {
        var chips: [String] = []
        if let skillName { chips.append(skillName) }
        if let agentName { chips.append(agentName) }
        if let tags {
            chips.append(contentsOf: tags.prefix(3))
        }
        return chips
    }

    private var accessibilityDescription: String {
        let readState = isUnread ? String(localized: "Unread.") : ""
        let timeAgo = RelativeDateTimeFormatter().localizedString(for: timestamp, relativeTo: .now)
        return "\(readState) \(severity.accessibilityLabel). \(title). \(subtitle). \(timeAgo)"
    }
}

#Preview("Normal") {
    AgentCardView(
        icon: "bolt.fill",
        title: "Daily Summary Generated",
        subtitle: "Your agent processed 12 tasks and completed 10 successfully.",
        severity: .info,
        timestamp: Date().addingTimeInterval(-3600),
        skillName: "summarizer",
        agentName: "MainAgent"
    )
    .padding()
}

#Preview("Unread Critical") {
    AgentCardView(
        icon: "exclamationmark.shield.fill",
        title: "Suspicious Domain Contacted",
        subtitle: "Agent attempted connection to unknown-api.xyz which is not in the allowlist.",
        severity: .critical,
        timestamp: Date().addingTimeInterval(-120),
        skillName: "web_scraper",
        isUnread: true
    )
    .padding()
}
