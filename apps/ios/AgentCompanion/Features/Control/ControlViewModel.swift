import Foundation
import SwiftUI

/// View model for the Control tab.
/// Manages instance status, active runs, quick actions, and routing toggles.
@MainActor
final class ControlViewModel: ObservableObject {

    // MARK: - Instance State

    @Published var instances: [Instance] = []
    @Published var selectedInstance: Instance?
    @Published var loadState: LoadState = .idle

    // MARK: - Active Runs

    @Published var activeRuns: [ActiveRun] = []

    // MARK: - Routing Toggles

    @Published var routeToInbox: Bool = true
    @Published var routeToTelegram: Bool = false
    @Published var routeToEmail: Bool = false
    @Published var structuredMode: Bool = true

    // MARK: - Confirmation State

    @Published var pendingAction: ConfirmableAction? = nil

    enum LoadState {
        case idle, loading, loaded, error(String)
    }

    enum ConfirmableAction: Identifiable {
        case pause, killSwitch, stopRun(ActiveRun)

        var id: String {
            switch self {
            case .pause: "pause"
            case .killSwitch: "kill"
            case .stopRun(let run): "stop-\(run.id)"
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .pause: "Pause Instance"
            case .killSwitch: "Kill Switch"
            case .stopRun: "Stop Run"
            }
        }

        var message: LocalizedStringKey {
            switch self {
            case .pause:
                "This will pause all event ingestion for this instance. No new data will be processed until you resume."
            case .killSwitch:
                "This will immediately revoke all integration tokens, pause the instance, and reject all incoming events. You will need to re-pair to resume."
            case .stopRun(let run):
                "This will cancel the \(run.skillName) run. The agent may not stop immediately."
            }
        }

        var buttonLabel: LocalizedStringKey {
            switch self {
            case .pause: "Pause"
            case .killSwitch: "Activate Kill Switch"
            case .stopRun: "Stop"
            }
        }

        var isDestructive: Bool {
            switch self {
            case .pause: false
            case .killSwitch, .stopRun: true
            }
        }
    }

    // MARK: - Load

    func loadInitial() async {
        guard loadState != .loading else { return }
        loadState = .loading

        do {
            instances = try await APIService.shared.fetchInstances()
            if selectedInstance == nil {
                selectedInstance = instances.first
            }
            loadState = .loaded
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    // MARK: - Quick Actions

    func pauseInstance() {
        pendingAction = .pause
    }

    func resumeInstance() {
        guard var instance = selectedInstance,
              let index = instances.firstIndex(where: { $0.id == instance.id }) else { return }
        // In production this calls the API; here we update locally
        Haptics.success()
        // Instance is a let-struct, so we rebuild
        let resumed = Instance(
            id: instance.id, name: instance.name, mode: .active,
            health: instance.health, lastSeen: instance.lastSeen, createdAt: instance.createdAt
        )
        instances[index] = resumed
        selectedInstance = resumed
    }

    func triggerKillSwitch() {
        pendingAction = .killSwitch
    }

    func testRun() {
        Haptics.success()
        let run = ActiveRun(
            id: UUID(),
            skillName: "connectivity_test",
            agentName: "system",
            startedAt: Date(),
            progress: 0.0,
            status: .running
        )
        activeRuns.insert(run, at: 0)
        simulateProgress(for: run.id)
    }

    func stopRun(_ run: ActiveRun) {
        pendingAction = .stopRun(run)
    }

    func confirmAction() {
        guard let action = pendingAction else { return }
        switch action {
        case .pause:
            Haptics.warning()
            updateSelectedInstanceMode(.paused)
        case .killSwitch:
            Haptics.destructive()
            updateSelectedInstanceMode(.safe)
        case .stopRun(let run):
            Haptics.destructive()
            if let index = activeRuns.firstIndex(where: { $0.id == run.id }) {
                activeRuns[index].status = .stopping
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.activeRuns.removeAll { $0.id == run.id }
                }
            }
        }
        pendingAction = nil
    }

    // MARK: - Helpers

    private func updateSelectedInstanceMode(_ mode: InstanceMode) {
        guard let instance = selectedInstance,
              let index = instances.firstIndex(where: { $0.id == instance.id }) else { return }
        let updated = Instance(
            id: instance.id, name: instance.name, mode: mode,
            health: instance.health, lastSeen: instance.lastSeen, createdAt: instance.createdAt
        )
        instances[index] = updated
        selectedInstance = updated
    }

    private func simulateProgress(for runID: UUID) {
        for step in 1...10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.4) { [weak self] in
                guard let self,
                      let index = self.activeRuns.firstIndex(where: { $0.id == runID }) else { return }
                if step < 10 {
                    self.activeRuns[index].progress = Double(step) / 10.0
                } else {
                    self.activeRuns[index].progress = 1.0
                    self.activeRuns[index].status = .completed
                    Haptics.success()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        self?.activeRuns.removeAll { $0.id == runID }
                    }
                }
            }
        }
    }

    var isPaused: Bool {
        selectedInstance?.mode == .paused || selectedInstance?.mode == .safe
    }
}
