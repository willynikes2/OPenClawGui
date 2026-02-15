import SwiftUI

/// Security tab — "Trust center, simple, not scary."
///
/// Spec 4.5 sections:
/// - Today's Risk Summary (big number, most common detector, last critical)
/// - Alerts list (filter chips: All/Critical/Warning, cards with detector+explanation+action)
/// - Skill Trust List (trusted vs untrusted/unknown, disable/allowlist per item)
/// - Detector Settings (toggles + sensitivity slider)
struct SecurityView: View {
    @StateObject private var viewModel = SecurityViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.loadState {
                case .idle, .loading:
                    SkeletonCardList()
                        .padding(.top, Space.lg)

                case .error(let message):
                    EmptyStateView(
                        icon: "exclamationmark.icloud",
                        title: "Something Went Wrong",
                        description: LocalizedStringKey(message),
                        actionTitle: "Retry"
                    ) {
                        Task { await viewModel.loadInitial() }
                    }

                case .loaded:
                    securityContent
                }
            }
            .navigationTitle("Security")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    InstancePicker(
                        selectedInstance: $viewModel.selectedInstance,
                        instances: viewModel.instances
                    )
                }
            }
            .task {
                await viewModel.loadInitial()
            }
            .confirmationDialog(
                skillActionTitle,
                isPresented: Binding(
                    get: { viewModel.pendingSkillAction != nil },
                    set: { if !$0 { viewModel.pendingSkillAction = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let action = viewModel.pendingSkillAction {
                    Button(
                        action.action == .disable ? "Disable Skill" : "Add to Allowlist",
                        role: action.action == .disable ? .destructive : nil
                    ) {
                        viewModel.confirmSkillAction()
                    }
                    Button("Cancel", role: .cancel) {
                        viewModel.pendingSkillAction = nil
                    }
                }
            } message: {
                if let action = viewModel.pendingSkillAction {
                    switch action.action {
                    case .disable:
                        Text("This will mark \(action.skill.name) as untrusted and prevent it from sending events.")
                    case .allowlist:
                        Text("This will mark \(action.skill.name) as trusted. It will no longer trigger trust-related alerts.")
                    }
                }
            }
        }
    }

    private var skillActionTitle: LocalizedStringKey {
        guard let action = viewModel.pendingSkillAction else { return "Confirm" }
        return action.action == .disable ? "Disable Skill" : "Trust Skill"
    }

    // MARK: - Content

    private var securityContent: some View {
        ScrollView {
            VStack(spacing: Space.lg) {
                riskSummaryCard
                alertsSection
                skillTrustSection
                detectorSettingsSection
            }
            .padding(.horizontal, Space.lg)
            .padding(.bottom, Space.xxl)
        }
    }

    // MARK: - Risk Summary Card

    private var riskSummaryCard: some View {
        VStack(spacing: Space.md) {
            Label {
                Text("Today's Risk Summary")
                    .font(Typography.headline)
            } icon: {
                Image(systemName: "chart.bar.doc.horizontal")
                    .foregroundStyle(.tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Space.xl) {
                // Big number: alerts today
                VStack(spacing: Space.xs) {
                    Text("\(viewModel.alertsToday)")
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(viewModel.alertsToday > 0 ? AppColors.severityWarn : .primary)
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Text("Alerts Today")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "\(viewModel.alertsToday) alerts today"))

                Divider()
                    .frame(height: 48)

                // Most common detector + last critical
                VStack(alignment: .leading, spacing: Space.sm) {
                    if let detector = viewModel.mostCommonDetector {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Most Common")
                                .font(Typography.caption2)
                                .foregroundStyle(.tertiary)
                                .textCase(.uppercase)
                            Text(detector)
                                .font(Typography.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                        }
                    }

                    if let lastCritical = viewModel.lastCriticalDate {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Last Critical")
                                .font(Typography.caption2)
                                .foregroundStyle(.tertiary)
                                .textCase(.uppercase)
                            Text(lastCritical, style: .relative)
                                .font(Typography.caption)
                                .foregroundStyle(AppColors.severityCritical)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Last Critical")
                                .font(Typography.caption2)
                                .foregroundStyle(.tertiary)
                                .textCase(.uppercase)
                            Text("None")
                                .font(Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .cardStyle()
    }

    // MARK: - Alerts Section

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Label {
                Text("Alerts")
                    .font(Typography.headline)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.tint)
            }

            // Filter chips
            FilterChipRow(
                options: SecurityViewModel.AlertFilter.allCases,
                selection: $viewModel.alertFilter
            )

            if viewModel.filteredAlerts.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: Space.sm) {
                        Image(systemName: "shield.checkered")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("No alerts")
                            .font(Typography.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, Space.xl)
                    Spacer()
                }
                .cardStyle()
            } else {
                ForEach(viewModel.filteredAlerts) { alert in
                    NavigationLink {
                        AlertDetailFullView(alert: alert)
                    } label: {
                        alertCard(alert)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func alertCard(_ alert: SecurityAlert) -> some View {
        HStack(spacing: Space.md) {
            SeverityBadge(severity: alert.severity)

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.detectorName)
                    .font(Typography.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Text(alert.explanation)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Space.xs) {
                Text(alert.createdAt, style: .relative)
                    .font(Typography.caption2)
                    .foregroundStyle(.tertiary)

                Image(systemName: "chevron.right")
                    .font(Typography.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .cardStyle(isCritical: alert.severity == .critical)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(alert.severity.accessibilityLabel). \(alert.detectorName). \(alert.explanation)")
    }

    // MARK: - Skill Trust Section

    private var skillTrustSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Label {
                Text("Skill Trust")
                    .font(Typography.headline)
            } icon: {
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(.tint)
            }

            if viewModel.skills.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: Space.sm) {
                        Image(systemName: "puzzlepiece.extension")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("No skills observed yet")
                            .font(Typography.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, Space.xl)
                    Spacer()
                }
                .cardStyle()
            } else {
                // Trusted
                if !viewModel.trustedSkills.isEmpty {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("Trusted")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        ForEach(viewModel.trustedSkills) { skill in
                            skillRow(skill)
                        }
                    }
                }

                // Untrusted / Unknown
                if !viewModel.untrustedSkills.isEmpty {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("Untrusted / Unknown")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        ForEach(viewModel.untrustedSkills) { skill in
                            skillRow(skill)
                        }
                    }
                }
            }
        }
    }

    private func skillRow(_ skill: Skill) -> some View {
        HStack(spacing: Space.md) {
            Image(systemName: skill.trustStatus.icon)
                .font(Typography.body)
                .foregroundStyle(skill.trustStatus.color)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(Typography.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: Space.sm) {
                    if let lastRun = skill.lastRun {
                        Text("Last run \(lastRun, style: .relative) ago")
                            .font(Typography.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if !skill.observedBehaviors.isEmpty {
                        Text(skill.observedBehaviors.joined(separator: ", "))
                            .font(Typography.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Action button
            Menu {
                if skill.trustStatus != .trusted {
                    Button {
                        viewModel.requestAllowlistSkill(skill)
                    } label: {
                        Label("Allowlist", systemImage: "checkmark.shield")
                    }
                }
                if skill.trustStatus != .untrusted {
                    Button(role: .destructive) {
                        viewModel.requestDisableSkill(skill)
                    } label: {
                        Label("Disable", systemImage: "xmark.shield")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "Actions for \(skill.name)"))
        }
        .cardStyle()
    }

    // MARK: - Detector Settings Section

    private var detectorSettingsSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Label {
                Text("Detector Settings")
                    .font(Typography.headline)
            } icon: {
                Image(systemName: "gearshape.2")
                    .foregroundStyle(.tint)
            }

            ForEach(viewModel.detectors) { detector in
                detectorRow(detector)
            }
        }
    }

    private func detectorRow(_ detector: DetectorConfig) -> some View {
        VStack(spacing: Space.sm) {
            HStack(spacing: Space.md) {
                Image(systemName: detector.icon)
                    .font(Typography.body)
                    .foregroundStyle(.tint)
                    .frame(width: 24, alignment: .center)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Space.xs) {
                        Text(detector.name)
                            .font(Typography.subheadline)
                            .fontWeight(.medium)

                        if detector.isRequired {
                            Text("Required")
                                .font(Typography.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, Space.sm)
                                .padding(.vertical, 2)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { detector.isEnabled },
                    set: { _ in viewModel.toggleDetector(id: detector.id) }
                ))
                .labelsHidden()
                .disabled(detector.isRequired)
                .accessibilityLabel(detector.isRequired
                    ? String(localized: "\(detector.name), required, always enabled")
                    : String(localized: "\(detector.name), \(detector.isEnabled ? "enabled" : "disabled")")
                )
            }

            // Sensitivity picker
            if detector.isEnabled {
                HStack(spacing: Space.sm) {
                    Text("Sensitivity")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Picker("", selection: Binding(
                        get: { detector.sensitivity },
                        set: { viewModel.setSensitivity(id: detector.id, level: $0) }
                    )) {
                        ForEach(DetectorSensitivity.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                .padding(.leading, 36)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardStyle()
        .animation(.easeInOut(duration: 0.2), value: detector.isEnabled)
    }
}

// MARK: - Alert Detail (full)

struct AlertDetailFullView: View {
    let alert: SecurityAlert

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                SeverityBadge(severity: alert.severity)

                Text(alert.detectorName)
                    .font(Typography.title)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Explanation")
                        .font(Typography.headline)
                    Text(alert.explanation)
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                }
                .cardStyle()

                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Recommended Action")
                        .font(Typography.headline)

                    Label {
                        Text(alert.recommendedAction)
                            .font(Typography.body)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .cardStyle()

                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Details")
                        .font(Typography.headline)

                    HStack {
                        Text("Event ID")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(alert.eventID.uuidString.prefix(8))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    HStack {
                        Text("Detected at")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(alert.createdAt, style: .date)
                            .font(Typography.caption)
                            .foregroundStyle(.tertiary)
                        Text(alert.createdAt, style: .time)
                            .font(Typography.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .cardStyle()
            }
            .padding(.horizontal, Space.lg)
            .padding(.bottom, Space.xxl)
        }
        .navigationTitle("Alert Detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SecurityView()
}
