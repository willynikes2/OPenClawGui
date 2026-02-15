import SwiftUI

/// Settings tab — spec 4.6.
///
/// Sections:
/// - Account + devices
/// - Instances (manage)
/// - Privacy & retention (data retention, redaction controls, export + delete)
/// - Notifications (categories, quiet hours)
/// - Voice & playback
/// - Advanced (logs export, cache)
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            List {
                accountSection
                instancesSection
                privacySection
                notificationsSection
                voiceSection
                advancedSection
            }
            .navigationTitle("Settings")
            .task {
                await viewModel.loadSettings()
            }
            // PII warning alert
            .alert(
                Text("Disable PII Redaction?"),
                isPresented: $viewModel.showPIIWarning
            ) {
                Button("Disable Anyway", role: .destructive) {
                    viewModel.confirmDisablePII()
                }
                Button("Keep Enabled", role: .cancel) {}
            } message: {
                Text("Disabling PII redaction means emails, phone numbers, API keys, and other sensitive data will be stored without redaction. This is not recommended.")
            }
            // Destructive action confirmation
            .confirmationDialog(
                viewModel.pendingDestructiveAction?.title ?? "Confirm",
                isPresented: Binding(
                    get: { viewModel.pendingDestructiveAction != nil },
                    set: { if !$0 { viewModel.pendingDestructiveAction = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let action = viewModel.pendingDestructiveAction {
                    Button(action.buttonLabel, role: .destructive) {
                        viewModel.confirmDestructiveAction()
                    }
                    Button("Cancel", role: .cancel) {
                        viewModel.pendingDestructiveAction = nil
                    }
                }
            } message: {
                if let action = viewModel.pendingDestructiveAction {
                    Text(action.message)
                }
            }
        }
    }

    // MARK: - Account + Devices

    private var accountSection: some View {
        Section {
            // Profile row
            HStack(spacing: Space.md) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Account")
                        .font(Typography.headline)

                    if !viewModel.userEmail.isEmpty {
                        Text(viewModel.userEmail)
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not signed in")
                            .font(Typography.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.vertical, Space.xs)

            // Devices
            NavigationLink {
                DeviceManagementView(viewModel: viewModel)
            } label: {
                Label {
                    HStack {
                        Text("Devices")
                        Spacer()
                        Text("\(viewModel.devices.count)")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "iphone.gen3")
                }
            }
        } header: {
            Text("Account")
        }
    }

    // MARK: - Instances

    private var instancesSection: some View {
        Section {
            if viewModel.instances.isEmpty {
                HStack {
                    Image(systemName: "server.rack")
                        .foregroundStyle(.tertiary)
                    Text("No instances configured")
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(viewModel.instances) { instance in
                    HStack(spacing: Space.md) {
                        Circle()
                            .fill(instance.health.dotColor)
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(instance.name)
                                .font(Typography.body)

                            if let lastSeen = instance.lastSeen {
                                Text("Last seen \(lastSeen, style: .relative) ago")
                                    .font(Typography.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        Button(role: .destructive) {
                            viewModel.requestRemoveInstance(instance)
                        } label: {
                            Image(systemName: "trash")
                                .font(Typography.caption)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(String(localized: "Remove \(instance.name)"))
                    }
                }
            }

            Button {
                // In production: navigate to onboarding/pairing
            } label: {
                Label("Add Instance", systemImage: "plus.circle")
            }
        } header: {
            Text("Instances")
        }
    }

    // MARK: - Privacy & Retention

    private var privacySection: some View {
        Section {
            // Data Retention Picker
            NavigationLink {
                DataRetentionPicker(selection: $viewModel.dataRetention)
            } label: {
                Label {
                    HStack {
                        Text("Data Retention")
                        Spacer()
                        Text(viewModel.dataRetention.rawValue)
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }

            // Redaction controls
            Toggle(isOn: Binding(
                get: { viewModel.redactPII },
                set: { newValue in
                    if !newValue {
                        viewModel.attemptDisablePII()
                    } else {
                        viewModel.redactPII = true
                    }
                }
            )) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Redact PII")
                        Text("Emails, phone numbers, API keys")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "eye.slash")
                }
            }

            Toggle(isOn: $viewModel.storeRawOutput) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Store Raw Output")
                        Text("Keep full agent output text")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "doc.text")
                }
            }

            Toggle(isOn: $viewModel.storeTelemetry) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Store Telemetry")
                        Text("Process names, domains, paths")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "chart.bar")
                }
            }

            // Export data
            Button {
                viewModel.showExportSheet = true
            } label: {
                Label("Export Data", systemImage: "square.and.arrow.up")
            }
            .sheet(isPresented: $viewModel.showExportSheet) {
                ExportDataSheet(viewModel: viewModel)
            }

            // Delete all data
            Button(role: .destructive) {
                viewModel.requestDeleteData()
            } label: {
                Label("Delete All Data", systemImage: "trash")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Privacy & Data")
        } footer: {
            Text("PII redaction automatically removes emails, phone numbers, and API keys before storing events. Disabling this is not recommended.")
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            Toggle(isOn: $viewModel.notificationsEnabled) {
                Label("Enable Notifications", systemImage: "bell.badge")
            }

            if viewModel.notificationsEnabled {
                // Notification categories
                Toggle(isOn: $viewModel.notifyCritical) {
                    Label {
                        HStack(spacing: Space.sm) {
                            Text("Critical Alerts")
                            SeverityBadge(severity: .critical)
                        }
                    } icon: {
                        Image(systemName: "xmark.octagon")
                    }
                }
                .disabled(true) // Critical always on
                .accessibilityHint(String(localized: "Critical alerts cannot be disabled"))

                Toggle(isOn: $viewModel.notifyWarning) {
                    Label {
                        HStack(spacing: Space.sm) {
                            Text("Warnings")
                            SeverityBadge(severity: .warn)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                }

                Toggle(isOn: $viewModel.notifyInfo) {
                    Label {
                        HStack(spacing: Space.sm) {
                            Text("Info Events")
                            SeverityBadge(severity: .info)
                        }
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                }

                // Quiet Hours
                Divider()

                Toggle(isOn: $viewModel.quietHoursEnabled) {
                    Label("Quiet Hours", systemImage: "moon.fill")
                }

                if viewModel.quietHoursEnabled {
                    DatePicker(
                        "From",
                        selection: $viewModel.quietHoursStart,
                        displayedComponents: .hourAndMinute
                    )
                    .padding(.leading, Space.xxl)

                    DatePicker(
                        "To",
                        selection: $viewModel.quietHoursEnd,
                        displayedComponents: .hourAndMinute
                    )
                    .padding(.leading, Space.xxl)
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Push notifications never contain sensitive content. A generic message is shown, then data is fetched inside the app.")
        }
    }

    // MARK: - Voice & Playback

    private var voiceSection: some View {
        Section {
            Picker(selection: $viewModel.ttsRate) {
                ForEach(TTSRate.allCases) { rate in
                    Text(rate.rawValue).tag(rate)
                }
            } label: {
                Label("Speech Rate", systemImage: "speaker.wave.2")
            }

            Toggle(isOn: $viewModel.autoPlayTTS) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-Play on Open")
                        Text("Read events aloud when opened")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "play.circle")
                }
            }
        } header: {
            Text("Voice & Playback")
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        Section {
            // Cache size
            HStack {
                Label("Cache Size", systemImage: "internaldrive")
                Spacer()
                Text(viewModel.cacheSize)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }

            // Clear cache
            Button(role: .destructive) {
                viewModel.requestClearCache()
            } label: {
                Label("Clear Cache", systemImage: "xmark.bin")
                    .foregroundStyle(.red)
            }

            // Export logs
            if let logsURL = viewModel.exportLogs() {
                ShareLink(item: logsURL) {
                    Label("Export Logs", systemImage: "doc.text.magnifyingglass")
                }
            }

            // App version
            HStack {
                Label("Version", systemImage: "info.circle")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    .font(Typography.caption)
                    .foregroundStyle(.tertiary)
            }
        } header: {
            Text("Advanced")
        }
    }
}

// MARK: - Data Retention Picker

struct DataRetentionPicker: View {
    @Binding var selection: DataRetention
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(DataRetention.allCases) { option in
                Button {
                    Haptics.selection()
                    selection = option
                    dismiss()
                } label: {
                    HStack(spacing: Space.md) {
                        Image(systemName: option.icon)
                            .font(Typography.headline)
                            .foregroundStyle(.tint)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.rawValue)
                                .font(Typography.body)
                                .foregroundStyle(.primary)

                            if let days = option.days {
                                Text("Events older than \(days) days will be automatically deleted")
                                    .font(Typography.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Events are kept indefinitely")
                                    .font(Typography.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if selection == option {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .navigationTitle("Data Retention")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Device Management

struct DeviceManagementView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        List {
            if viewModel.devices.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: Space.sm) {
                        Image(systemName: "iphone.slash")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("No paired devices")
                            .font(Typography.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, Space.xl)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.devices) { device in
                    HStack(spacing: Space.md) {
                        Image(systemName: deviceIcon(device.platform))
                            .font(Typography.headline)
                            .foregroundStyle(.tint)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: Space.sm) {
                                Text(device.name)
                                    .font(Typography.body)

                                if device.isCurrent {
                                    Text("This Device")
                                        .font(Typography.caption2)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, Space.sm)
                                        .padding(.vertical, 2)
                                        .background(Color(.tertiarySystemFill))
                                        .clipShape(Capsule())
                                }
                            }

                            if let lastSeen = device.lastSeen {
                                Text("Last seen \(lastSeen, style: .relative) ago")
                                    .font(Typography.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        if !device.isCurrent {
                            Button(role: .destructive) {
                                viewModel.requestRevokeDevice(device)
                            } label: {
                                Text("Revoke")
                                    .font(Typography.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .navigationTitle("Devices")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func deviceIcon(_ platform: String) -> String {
        switch platform {
        case "ios": "iphone.gen3"
        case "android": "candybarphone"
        case "web": "laptopcomputer"
        default: "desktopcomputer"
        }
    }
}

// MARK: - Export Data Sheet

struct ExportDataSheet: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let url = viewModel.exportData() {
                        ShareLink(item: url) {
                            Label("Export Events (JSON)", systemImage: "doc.badge.arrow.up")
                        }
                    }

                    if let url = viewModel.exportLogs() {
                        ShareLink(item: url) {
                            Label("Export Logs", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                } header: {
                    Text("Choose Export")
                } footer: {
                    Text("Exported data includes all locally cached events. No server data is included unless cached.")
                }
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    SettingsView()
}
