import SwiftUI

/// Premium reader screen for a single event.
///
/// Spec 4.3 layout:
/// - Header: title, source chips (instance, agent, skill), severity badge, timestamp
/// - Content: rich view (default) with raw output toggle, copy button, read aloud button
/// - Security panel: triggered alerts, tap → alert detail
/// - Actions: pin, tag, share, export
struct EventDetailView: View {
    @StateObject private var viewModel: EventDetailViewModel
    @Environment(\.dismiss) private var dismiss

    init(event: AgentEvent) {
        _viewModel = StateObject(wrappedValue: EventDetailViewModel(event: event))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                headerSection
                contentSection
                securityPanel
                actionsSection
            }
            .padding(.horizontal, Space.lg)
            .padding(.bottom, Space.xxl)
        }
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                readAloudButton
            }
        }
        .task {
            await viewModel.loadDetail()
        }
        .onDisappear {
            viewModel.stopSpeaking()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            // Severity badge + timestamp row
            HStack {
                SeverityBadge(severity: viewModel.event.severity)

                Spacer()

                Text(viewModel.event.timestamp, style: .date)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                +
                Text(" ")
                    .font(Typography.caption)
                +
                Text(viewModel.event.timestamp, style: .time)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }

            // Title
            Text(viewModel.event.title)
                .font(Typography.title)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            // Source chips: instance, agent, skill
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.sm) {
                    sourceChip(icon: "server.rack", label: viewModel.event.instanceID.uuidString.prefix(8))
                    sourceChip(icon: "cpu", label: viewModel.event.agentName)
                    sourceChip(icon: "puzzlepiece.extension", label: viewModel.event.skillName)
                    sourceChip(icon: "antenna.radiowaves.left.and.right", label: viewModel.event.sourceType.rawValue)
                }
            }

            // Tags
            if let tags = viewModel.event.tags, !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.xs) {
                        ForEach(tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(Typography.caption2)
                                .foregroundStyle(.tint)
                                .padding(.horizontal, Space.sm)
                                .padding(.vertical, Space.xs)
                                .background(Color.accentColor.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // PII redaction notice
            if viewModel.event.piiRedacted {
                Label {
                    Text("Some content was redacted for privacy.")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "eye.slash")
                        .font(Typography.caption)
                        .foregroundStyle(.orange)
                }
            }

            Divider()
        }
    }

    private func sourceChip(icon: String, label: some StringProtocol) -> some View {
        Label {
            Text(label)
                .font(Typography.caption)
        } icon: {
            Image(systemName: icon)
                .font(Typography.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .background(Color(.tertiarySystemFill))
        .clipShape(Capsule())
    }

    // MARK: - Content

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            // View mode toggle
            HStack {
                Text("Content")
                    .font(Typography.headline)

                Spacer()

                if viewModel.event.bodyRaw != nil || viewModel.hasStructuredContent {
                    Picker("", selection: $viewModel.showRawOutput) {
                        Text("Rich").tag(false)
                        Text("Raw").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
            }

            // Content body
            if viewModel.showRawOutput {
                rawContentView
            } else {
                richContentView
            }
        }
    }

    // MARK: - Rich Content View

    @ViewBuilder
    private var richContentView: some View {
        if viewModel.hasStructuredContent {
            VStack(alignment: .leading, spacing: Space.md) {
                ForEach(viewModel.structuredEntries, id: \.key) { entry in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(entry.key.capitalized)
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Text(entry.value)
                            .font(Typography.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .cardStyle()
                }
            }
        } else if let raw = viewModel.event.bodyRaw {
            Text(raw)
                .font(Typography.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .cardStyle()
        } else {
            switch viewModel.loadState {
            case .loadingRaw:
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.regular)
                    Spacer()
                }
                .padding(.vertical, Space.xl)

            case .errorRaw(let message):
                Label {
                    Text(message)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                .cardStyle()

            case .loaded:
                Text("No content available.")
                    .font(Typography.body)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
    }

    // MARK: - Raw Content View

    @ViewBuilder
    private var rawContentView: some View {
        if let raw = viewModel.event.bodyRaw {
            VStack(alignment: .trailing, spacing: Space.sm) {
                // Copy button
                Button {
                    viewModel.copyRawToClipboard()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(Typography.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(String(localized: "Copy raw output to clipboard"))

                // Raw text
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(raw)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .cardStyle()
            }
        } else {
            switch viewModel.loadState {
            case .loadingRaw:
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, Space.xl)
            default:
                Text("Raw output not available.")
                    .font(Typography.body)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
    }

    // MARK: - Security Panel

    @ViewBuilder
    private var securityPanel: some View {
        if !viewModel.alerts.isEmpty {
            VStack(alignment: .leading, spacing: Space.md) {
                Label {
                    Text("Security Alerts")
                        .font(Typography.headline)
                } icon: {
                    Image(systemName: "shield.exclamationmark")
                        .foregroundStyle(AppColors.severityCritical)
                }

                Text("This event triggered the following detectors:")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)

                ForEach(viewModel.alerts) { alert in
                    NavigationLink {
                        AlertDetailView(alert: alert)
                    } label: {
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

                            Image(systemName: "chevron.right")
                                .font(Typography.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .cardStyle(isCritical: alert.severity == .critical)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Divider()

            Text("Actions")
                .font(Typography.headline)

            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ],
                spacing: Space.md
            ) {
                actionButton(
                    icon: viewModel.isPinned ? "pin.fill" : "pin",
                    label: "Pin",
                    action: viewModel.togglePin
                )

                actionButton(
                    icon: "tag",
                    label: "Tag",
                    action: { viewModel.showTagSheet = true }
                )

                ShareLink(
                    item: shareText,
                    subject: Text(viewModel.event.title)
                ) {
                    actionButtonLabel(icon: "square.and.arrow.up", label: "Share")
                }

                actionButton(
                    icon: "square.and.arrow.down",
                    label: "Export",
                    action: {}
                )
            }
        }
        .sheet(isPresented: $viewModel.showTagSheet) {
            tagSheet
        }
    }

    private func actionButton(icon: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionButtonLabel(icon: icon, label: label)
        }
        .buttonStyle(.plain)
    }

    private func actionButtonLabel(icon: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: Space.xs) {
            Image(systemName: icon)
                .font(Typography.headline)
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: Radii.button))

            Text(label)
                .font(Typography.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Read Aloud Button

    private var readAloudButton: some View {
        Button {
            viewModel.toggleReadAloud()
        } label: {
            Image(systemName: viewModel.isSpeaking ? "speaker.slash.fill" : "speaker.wave.2.fill")
        }
        .accessibilityLabel(
            viewModel.isSpeaking
                ? String(localized: "Stop reading")
                : String(localized: "Read aloud")
        )
    }

    // MARK: - Tag Sheet

    private var tagSheet: some View {
        NavigationStack {
            Form {
                Section("Add Tag") {
                    TextField(String(localized: "Tag name"), text: $viewModel.newTag)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if let tags = viewModel.event.tags, !tags.isEmpty {
                    Section("Current Tags") {
                        ForEach(tags, id: \.self) { tag in
                            Label(tag, systemImage: "tag")
                        }
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { viewModel.showTagSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Share

    private var shareText: String {
        var text = "[\(viewModel.event.severity.rawValue.uppercased())] \(viewModel.event.title)\n"
        text += "Agent: \(viewModel.event.agentName) / Skill: \(viewModel.event.skillName)\n"
        text += "Time: \(viewModel.event.timestamp.formatted())\n"
        if let raw = viewModel.event.bodyRaw {
            text += "\n\(raw)"
        }
        return text
    }
}

// MARK: - Alert Detail Placeholder

struct AlertDetailView: View {
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
                    Text(alert.recommendedAction)
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                }
                .cardStyle()

                Text(alert.createdAt, style: .date)
                    .font(Typography.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Space.lg)
        }
        .navigationTitle("Alert Detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        EventDetailView(event: AgentEvent(
            id: UUID(),
            instanceID: UUID(),
            sourceType: .skill,
            agentName: "MainAgent",
            skillName: "summarizer",
            timestamp: Date().addingTimeInterval(-3600),
            title: "Daily Summary Generated",
            bodyStructuredJSON: [
                "summary": AnyCodable("Processed 12 tasks, 10 completed successfully."),
                "tasks_completed": AnyCodable(10),
                "tasks_failed": AnyCodable(2),
            ],
            tags: ["daily", "summary"],
            severity: .info,
            piiRedacted: false,
            createdAt: Date()
        ))
    }
}
