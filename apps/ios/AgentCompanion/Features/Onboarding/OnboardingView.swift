import SwiftUI

/// Multi-step onboarding flow presented as a full-screen modal.
/// Steps: Welcome → Pairing Method → Privacy Explainer → Connectivity Test
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = OnboardingViewModel()

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.step {
                case .welcome:
                    WelcomeStepView(onContinue: viewModel.advance)
                case .pairingMethod:
                    PairingMethodStepView(viewModel: viewModel)
                case .privacy:
                    PrivacyExplainerStepView(viewModel: viewModel)
                case .connectivityTest:
                    ConnectivityTestStepView(viewModel: viewModel) {
                        dismiss()
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.step)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if viewModel.step != .welcome {
                        Button {
                            viewModel.goBack()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel(String(localized: "Go back"))
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

// MARK: - View Model

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var step: OnboardingStep = .welcome

    // Pairing
    @Published var pairingMethod: PairingMethod? = nil
    @Published var pasteToken: String = ""

    // Privacy toggles
    @Published var storeRawOutput: Bool = false
    @Published var storeTelemetry: Bool = true
    @Published var redactPII: Bool = true
    @Published var showPIIWarning: Bool = false

    // Connectivity
    @Published var connectivityState: ConnectivityState = .idle

    func advance() {
        switch step {
        case .welcome: step = .pairingMethod
        case .pairingMethod: step = .privacy
        case .privacy: step = .connectivityTest
        case .connectivityTest: break
        }
    }

    func goBack() {
        switch step {
        case .welcome: break
        case .pairingMethod: step = .welcome
        case .privacy: step = .pairingMethod
        case .connectivityTest: step = .privacy
        }
    }

    func attemptDisablePII() {
        showPIIWarning = true
    }

    func confirmDisablePII() {
        redactPII = false
        showPIIWarning = false
    }

    func startConnectivityTest() {
        connectivityState = .testing(completedSteps: 0)

        // Simulate step-by-step progress
        let steps = ConnectivityStep.allCases
        for (index, _) in steps.enumerated() {
            let delay = Double(index + 1) * 0.8
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                if index < steps.count - 1 {
                    self.connectivityState = .testing(completedSteps: index + 1)
                } else {
                    self.connectivityState = .success
                    Haptics.success()
                }
            }
        }
    }
}

enum OnboardingStep: Int, CaseIterable {
    case welcome, pairingMethod, privacy, connectivityTest
}

enum PairingMethod: String, CaseIterable {
    case scanQR, pasteToken, telegramBridge
}

enum ConnectivityState: Equatable {
    case idle
    case testing(completedSteps: Int)
    case success
    case failed(String)
}

enum ConnectivityStep: String, CaseIterable {
    case resolvingHost = "Resolving host"
    case tlsHandshake = "Establishing secure connection"
    case authenticating = "Authenticating"
    case fetchingEvents = "Fetching initial data"

    var icon: String {
        switch self {
        case .resolvingHost: "globe"
        case .tlsHandshake: "lock.shield"
        case .authenticating: "person.badge.key"
        case .fetchingEvents: "arrow.down.doc"
        }
    }
}
