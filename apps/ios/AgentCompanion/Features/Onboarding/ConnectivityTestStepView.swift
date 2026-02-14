import SwiftUI

/// Step 4: Connectivity test with step-by-step progress.
/// Success state leads to "Go to Inbox".
struct ConnectivityTestStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let steps = ConnectivityStep.allCases

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Header
            Group {
                switch viewModel.connectivityState {
                case .idle, .testing:
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                        .symbolEffect(
                            .variableColor.iterative,
                            options: reduceMotion ? .nonRepeating : .repeating
                        )
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.red)
                }
            }
            .accessibilityHidden(true)
            .padding(.bottom, Space.lg)

            Text(headerTitle)
                .font(Typography.title)
                .fontWeight(.bold)
                .padding(.bottom, Space.xs)

            Text(headerSubtitle)
                .font(Typography.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.xl)
                .padding(.bottom, Space.xxl)

            // Step list
            VStack(alignment: .leading, spacing: Space.lg) {
                ForEach(Array(steps.enumerated()), id: \.element) { index, step in
                    stepRow(step: step, index: index)
                }
            }
            .padding(.horizontal, Space.xxl)

            Spacer()
            Spacer()

            // Action button
            Group {
                switch viewModel.connectivityState {
                case .idle:
                    Button {
                        viewModel.startConnectivityTest()
                    } label: {
                        Text("Test Connection")
                            .font(Typography.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Space.md)
                    }
                    .buttonStyle(.borderedProminent)

                case .testing:
                    ProgressView()
                        .controlSize(.regular)
                        .padding(.vertical, Space.lg)

                case .success:
                    Button(action: onComplete) {
                        Text("Go to Inbox")
                            .font(Typography.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Space.md)
                    }
                    .buttonStyle(.borderedProminent)

                case .failed(let message):
                    VStack(spacing: Space.sm) {
                        Text(message)
                            .font(Typography.caption)
                            .foregroundStyle(.red)

                        Button {
                            viewModel.startConnectivityTest()
                        } label: {
                            Text("Retry")
                                .font(Typography.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Space.md)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .controlSize(.large)
            .clipShape(RoundedRectangle(cornerRadius: Radii.button))
            .padding(.horizontal, Space.xl)
            .padding(.bottom, Space.xxl)
        }
    }

    // MARK: - Step Row

    private func stepRow(step: ConnectivityStep, index: Int) -> some View {
        let state = stepState(for: index)

        return HStack(spacing: Space.md) {
            Group {
                switch state {
                case .pending:
                    Image(systemName: step.icon)
                        .foregroundStyle(.tertiary)
                case .inProgress:
                    ProgressView()
                        .controlSize(.small)
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            .frame(width: 24, height: 24)

            Text(String(localized: String.LocalizationValue(step.rawValue)))
                .font(Typography.body)
                .foregroundStyle(state == .pending ? .tertiary : .primary)

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private func stepState(for index: Int) -> StepState {
        switch viewModel.connectivityState {
        case .idle:
            return .pending
        case .testing(let completedSteps):
            if index < completedSteps {
                return .completed
            } else if index == completedSteps {
                return .inProgress
            } else {
                return .pending
            }
        case .success:
            return .completed
        case .failed:
            if index < steps.count - 1 {
                return .completed
            }
            return .failed
        }
    }

    // MARK: - Copy

    private var headerTitle: LocalizedStringKey {
        switch viewModel.connectivityState {
        case .idle: "Connectivity Test"
        case .testing: "Connecting..."
        case .success: "All Set!"
        case .failed: "Connection Failed"
        }
    }

    private var headerSubtitle: LocalizedStringKey {
        switch viewModel.connectivityState {
        case .idle: "We'll verify the connection to your Claw instance."
        case .testing: "Checking connectivity with your instance."
        case .success: "Your instance is connected and ready to go."
        case .failed: "We couldn't reach your instance. Check your settings and try again."
        }
    }
}

private enum StepState {
    case pending, inProgress, completed, failed
}

#Preview("Idle") {
    NavigationStack {
        ConnectivityTestStepView(viewModel: OnboardingViewModel(), onComplete: {})
    }
}
