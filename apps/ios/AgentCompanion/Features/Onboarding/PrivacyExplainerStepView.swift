import SwiftUI

/// Step 3: Privacy explainer — must be shown, cannot be skipped.
/// Shows what's collected, what's not, and privacy toggles.
struct PrivacyExplainerStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var showLearnMore = false

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xl) {
                // Header
                VStack(spacing: Space.sm) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)

                    Text("Your Privacy Matters")
                        .font(Typography.title)
                        .fontWeight(.bold)

                    Text("Here's exactly what AgentCompanion collects.")
                        .font(Typography.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, Space.xl)

                // What's collected
                collectedSection

                // What's NOT collected
                notCollectedSection

                // Learn more expandable
                DisclosureGroup(isExpanded: $showLearnMore) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("All data is encrypted in transit (TLS) and at rest (envelope encryption). Push notifications never contain sensitive content. You can export or delete your data at any time from Settings.")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, Space.sm)
                } label: {
                    Text("Learn more about data handling")
                        .font(Typography.subheadline)
                        .foregroundStyle(.tint)
                }
                .padding(.horizontal, Space.xl)

                // Privacy toggles
                togglesSection

                Spacer(minLength: Space.xxl)

                // Continue
                Button(action: viewModel.advance) {
                    Text("Continue")
                        .font(Typography.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.md)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .clipShape(RoundedRectangle(cornerRadius: Radii.button))
                .padding(.horizontal, Space.xl)
                .padding(.bottom, Space.xxl)
            }
        }
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
    }

    // MARK: - Collected

    private var collectedSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Label {
                Text("What's collected")
                    .font(Typography.headline)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                collectedItem("Event titles and summaries")
                collectedItem("Domain names contacted")
                collectedItem("Process names")
                collectedItem("Timestamps")
            }
            .padding(.leading, Space.xxl)
        }
        .padding(.horizontal, Space.xl)
    }

    private func collectedItem(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: Space.sm) {
            Circle()
                .fill(.secondary)
                .frame(width: 4, height: 4)
            Text(text)
                .font(Typography.body)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Not Collected

    private var notCollectedSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Label {
                Text("Not collected by default")
                    .font(Typography.headline)
            } icon: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                collectedItem("Full email bodies")
                collectedItem("File contents")
                collectedItem("Passwords and secrets")
            }
            .padding(.leading, Space.xxl)
        }
        .padding(.horizontal, Space.xl)
    }

    // MARK: - Toggles

    private var togglesSection: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, Space.xl)
                .padding(.bottom, Space.md)

            VStack(spacing: Space.sm) {
                privacyToggle(
                    icon: "doc.text",
                    title: "Store Raw Output",
                    subtitle: "Keep full unstructured agent output. Off by default.",
                    isOn: $viewModel.storeRawOutput
                )

                privacyToggle(
                    icon: "chart.bar",
                    title: "Store Telemetry",
                    subtitle: "Process names, domains, and file path metadata.",
                    isOn: $viewModel.storeTelemetry
                )

                // PII toggle with warning
                HStack(spacing: Space.md) {
                    Image(systemName: "eye.slash.fill")
                        .font(Typography.body)
                        .foregroundStyle(.tint)
                        .frame(width: 24, alignment: .center)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Redact PII")
                            .font(Typography.body)

                        Text("Automatically redact emails, phone numbers, and API keys.")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { viewModel.redactPII },
                        set: { newValue in
                            if !newValue {
                                viewModel.attemptDisablePII()
                            } else {
                                viewModel.redactPII = true
                            }
                        }
                    ))
                    .labelsHidden()
                }
                .padding(.horizontal, Space.xl)
                .padding(.vertical, Space.sm)
            }
        }
    }

    private func privacyToggle(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
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
                Text(subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.sm)
    }
}

#Preview {
    NavigationStack {
        PrivacyExplainerStepView(viewModel: OnboardingViewModel())
    }
}
