import SwiftUI

/// Control tab — "Control Center" feel.
///
/// Spec 4.4 sections:
/// - System Status (health, last seen, current mode)
/// - Active Runs (progress bars, stop button inline)
/// - Quick Actions (pause/resume, kill switch, test run)
/// - Routing (output destination toggles, structured mode)
/// - Every destructive action uses confirmation sheet + "Why this matters"
struct ControlView: View {
    @StateObject private var viewModel = ControlViewModel()

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
                    if viewModel.selectedInstance != nil {
                        controlContent
                    } else {
                        EmptyStateView(
                            icon: "slider.horizontal.3",
                            title: "No Instance Connected",
                            description: "Add a Claw instance to start managing your agents.",
                            actionTitle: "Add Instance",
                            action: {}
                        )
                    }
                }
            }
            .navigationTitle("Control")
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
                viewModel.pendingAction?.title ?? "Confirm",
                isPresented: Binding(
                    get: { viewModel.pendingAction != nil },
                    set: { if !$0 { viewModel.pendingAction = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let action = viewModel.pendingAction {
                    Button(action.buttonLabel, role: action.isDestructive ? .destructive : nil) {
                        viewModel.confirmAction()
                    }
                    Button("Cancel", role: .cancel) {
                        viewModel.pendingAction = nil
                    }
                }
            } message: {
                if let action = viewModel.pendingAction {
                    Text(action.message)
                }
            }
        }
    }

    // MARK: - Main Content

    private var controlContent: some View {
        ScrollView {
            VStack(spacing: Space.lg) {
                systemStatusCard
                activeRunsSection
                quickActionsSection
                routingSection
            }
            .padding(.horizontal, Space.lg)
            .padding(.bottom, Space.xxl)
        }
    }

    // MARK: - System Status Card

    private var systemStatusCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Label {
                Text("System Status")
                    .font(Typography.headline)
            } icon: {
                Image(systemName: "server.rack")
                    .foregroundStyle(.tint)
            }

            if let instance = viewModel.selectedInstance {
                HStack(spacing: Space.xl) {
                    statusItem(
                        label: "Health",
                        value: instance.health.label,
                        color: instance.health.dotColor
                    )

                    statusItem(
                        label: "Mode",
                        value: modeLabel(instance.mode),
                        color: modeColor(instance.mode)
                    )
                }

                if let lastSeen = instance.lastSeen {
                    HStack(spacing: Space.sm) {
                        Image(systemName: "clock")
                            .font(Typography.caption)
                            .foregroundStyle(.tertiary)
                        Text("Last seen \(lastSeen, style: .relative) ago")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .cardStyle()
    }

    private func statusItem(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: Space.sm) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)

                Text(value)
                    .font(Typography.headline)
                    .foregroundStyle(.primary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func modeLabel(_ mode: InstanceMode) -> String {
        switch mode {
        case .active: String(localized: "Active")
        case .paused: String(localized: "Paused")
        case .safe: String(localized: "Safe Mode")
        }
    }

    private func modeColor(_ mode: InstanceMode) -> Color {
        switch mode {
        case .active: AppColors.healthOK
        case .paused: AppColors.healthDegraded
        case .safe: AppColors.healthOffline
        }
    }

    // MARK: - Active Runs

    private var activeRunsSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Label {
                Text("Active Runs")
                    .font(Typography.headline)
            } icon: {
                Image(systemName: "play.circle")
                    .foregroundStyle(.tint)
            }

            if viewModel.activeRuns.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: Space.sm) {
                        Image(systemName: "moon.zzz")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("No active runs")
                            .font(Typography.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, Space.lg)
                    Spacer()
                }
            } else {
                ForEach(viewModel.activeRuns) { run in
                    activeRunRow(run)
                }
            }
        }
        .cardStyle()
    }

    private func activeRunRow(_ run: ActiveRun) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.skillName)
                        .font(Typography.subheadline)
                        .fontWeight(.medium)

                    Text(run.agentName)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                switch run.status {
                case .running:
                    Button {
                        viewModel.stopRun(run)
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                    }
                    .accessibilityLabel(String(localized: "Stop \(run.skillName)"))

                case .stopping:
                    ProgressView()
                        .controlSize(.small)

                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            ProgressView(value: run.progress, total: 1.0)
                .tint(run.status == .stopping ? .orange : .accentColor)

            HStack {
                Text("Started \(run.startedAt, style: .relative) ago")
                    .font(Typography.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                Text("\(Int(run.progress * 100))%")
                    .font(Typography.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(Space.md)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: Radii.button))
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Label {
                Text("Quick Actions")
                    .font(Typography.headline)
            } icon: {
                Image(systemName: "bolt.circle")
                    .foregroundStyle(.tint)
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: Space.md
            ) {
                // Pause / Resume
                if viewModel.isPaused {
                    quickActionButton(
                        icon: "play.fill",
                        label: "Resume",
                        color: .green,
                        action: viewModel.resumeInstance
                    )
                } else {
                    quickActionButton(
                        icon: "pause.fill",
                        label: "Pause",
                        color: .orange,
                        action: viewModel.pauseInstance
                    )
                }

                // Kill Switch
                quickActionButton(
                    icon: "power",
                    label: "Kill Switch",
                    color: .red,
                    action: viewModel.triggerKillSwitch
                )

                // Test Run
                quickActionButton(
                    icon: "play.circle",
                    label: "Test Run",
                    color: .blue,
                    action: viewModel.testRun
                )

                // Placeholder for future actions
                quickActionButton(
                    icon: "arrow.clockwise",
                    label: "Refresh",
                    color: .teal
                ) {
                    Task { await viewModel.loadInitial() }
                }
            }
        }
        .cardStyle()
    }

    private func quickActionButton(
        icon: String,
        label: LocalizedStringKey,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: Space.sm) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Radii.button))

                Text(label)
                    .font(Typography.caption)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.sm)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Routing

    private var routingSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Label {
                Text("Output Routing")
                    .font(Typography.headline)
            } icon: {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(.tint)
            }

            VStack(spacing: 0) {
                routingToggle(
                    icon: "tray.fill",
                    title: "In-App Inbox",
                    isOn: $viewModel.routeToInbox
                )
                Divider().padding(.leading, 44)

                routingToggle(
                    icon: "paperplane.fill",
                    title: "Telegram",
                    isOn: $viewModel.routeToTelegram
                )
                Divider().padding(.leading, 44)

                routingToggle(
                    icon: "envelope.fill",
                    title: "Email",
                    isOn: $viewModel.routeToEmail
                )
                Divider().padding(.leading, 44)

                routingToggle(
                    icon: "doc.richtext.fill",
                    title: "Structured Mode",
                    subtitle: "Send structured JSON instead of plain text.",
                    isOn: $viewModel.structuredMode
                )
            }
        }
        .cardStyle()
    }

    private func routingToggle(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: Space.md) {
            Image(systemName: icon)
                .font(Typography.body)
                .foregroundStyle(.tint)
                .frame(width: 24, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.body)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(.vertical, Space.sm)
    }
}

#Preview {
    ControlView()
}
