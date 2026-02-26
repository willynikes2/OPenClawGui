import SwiftUI

/// Approval card displayed in chat when a skill requests permission for a sensitive action.
///
/// Shows: skill name, action type icon, summary, risk level badge, evidence preview,
/// and three action buttons: Allow Once / Always Allow / Deny.
/// Expired or decided approvals show disabled state.
struct ApprovalCardView: View {
    let approvalId: UUID
    let skillName: String
    let action: ApprovalActionType
    let summary: String
    let riskLevel: ApprovalRiskLevel
    let evidence: [String: AnyCodable]?
    let status: ApprovalStatus
    let decision: String?
    let expiresAt: Date
    let onDecide: (String) -> Void

    private var isExpired: Bool {
        Date() > expiresAt
    }

    private var isActionable: Bool {
        status == .pending && !isExpired
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            header
            summaryText
            evidenceSection
            statusOrButtons
        }
        .padding(Space.lg)
        .background {
            RoundedRectangle(cornerRadius: Radii.card)
                .fill(cardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radii.card)
                .strokeBorder(borderColor, lineWidth: 1.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: action.icon)
                .font(Typography.headline)
                .foregroundStyle(riskColor)
                .frame(width: 32, height: 32)
                .background(riskColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Radii.button))

            VStack(alignment: .leading, spacing: 2) {
                Text(skillName)
                    .font(Typography.headline)
                    .lineLimit(1)

                Text(action.displayName)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            riskBadge
        }
    }

    private var riskBadge: some View {
        Text(riskLevel.displayName)
            .font(Typography.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .background(riskColor)
            .clipShape(Capsule())
    }

    // MARK: - Summary

    private var summaryText: some View {
        Text(summary)
            .font(Typography.body)
            .foregroundStyle(.primary)
    }

    // MARK: - Evidence

    @ViewBuilder
    private var evidenceSection: some View {
        if let evidence, !evidence.isEmpty {
            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(evidence.keys.sorted().prefix(4), id: \.self) { key in
                    HStack(alignment: .top, spacing: Space.sm) {
                        Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 80, alignment: .leading)
                        Text(String(describing: evidence[key]?.value ?? ""))
                            .font(Typography.caption)
                            .lineLimit(2)
                    }
                }
            }
            .padding(Space.sm)
            .background(Color(.systemFill))
            .clipShape(RoundedRectangle(cornerRadius: Radii.button))
        }
    }

    // MARK: - Status / Buttons

    @ViewBuilder
    private var statusOrButtons: some View {
        if isActionable {
            actionButtons
        } else {
            decidedStatus
        }
    }

    private var actionButtons: some View {
        HStack(spacing: Space.sm) {
            Button {
                Haptics.warning()
                onDecide("allow_once")
            } label: {
                Text("Allow Once")
                    .font(Typography.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .accessibilityLabel(String(localized: "Allow this action once"))

            Button {
                Haptics.warning()
                onDecide("allow_always")
            } label: {
                Text("Always Allow")
                    .font(Typography.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.green)
            .accessibilityLabel(String(localized: "Always allow this action"))

            Button {
                Haptics.destructive()
                onDecide("deny")
            } label: {
                Text("Deny")
                    .font(Typography.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .accessibilityLabel(String(localized: "Deny this action"))
        }
    }

    private var decidedStatus: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            Text(statusText)
                .font(Typography.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.sm)
        .background(Color(.systemFill))
        .clipShape(RoundedRectangle(cornerRadius: Radii.button))
    }

    // MARK: - Styling

    private var riskColor: Color {
        riskLevel == .critical ? AppColors.severityCritical : AppColors.severityWarn
    }

    private var cardBackground: Color {
        riskLevel == .critical ? AppColors.criticalTint : AppColors.cardBackground
    }

    private var borderColor: Color {
        isActionable ? riskColor.opacity(0.4) : Color.clear
    }

    private var statusIcon: String {
        if isExpired { return "clock.badge.xmark" }
        switch status {
        case .approved: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .expired: return "clock.badge.xmark"
        case .pending: return "hourglass"
        }
    }

    private var statusColor: Color {
        if isExpired { return .secondary }
        switch status {
        case .approved: return .green
        case .denied: return .red
        case .expired: return .secondary
        case .pending: return .orange
        }
    }

    private var statusText: String {
        if isExpired && status == .pending { return "Expired" }
        switch status {
        case .pending: return "Awaiting decision..."
        case .approved:
            let label = decision == "allow_always" ? "Always Allowed" : "Allowed (once)"
            return label
        case .denied: return "Denied"
        case .expired: return "Expired"
        }
    }

    private var accessibilityDescription: String {
        let base = "Approval request from \(skillName): \(summary). Risk level: \(riskLevel.displayName)."
        if isActionable {
            return base + " Awaiting your decision."
        }
        return base + " Status: \(statusText)."
    }
}

#Preview {
    VStack(spacing: Space.lg) {
        ApprovalCardView(
            approvalId: UUID(),
            skillName: "email-sender",
            action: .sendEmail,
            summary: "Skill wants to send 12 emails to external recipients",
            riskLevel: .warning,
            evidence: ["recipient_count": AnyCodable(12), "domain": AnyCodable("external.com")],
            status: .pending,
            decision: nil,
            expiresAt: Date().addingTimeInterval(300),
            onDecide: { _ in }
        )

        ApprovalCardView(
            approvalId: UUID(),
            skillName: "file-access",
            action: .accessSensitivePath,
            summary: "Skill wants to read ~/.ssh/id_rsa",
            riskLevel: .critical,
            evidence: ["path": AnyCodable("~/.ssh/id_rsa")],
            status: .denied,
            decision: "deny",
            expiresAt: Date().addingTimeInterval(300),
            onDecide: { _ in }
        )
    }
    .padding()
}
