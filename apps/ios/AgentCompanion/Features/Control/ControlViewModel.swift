import Foundation
import SwiftUI

/// View model for the Control tab.
/// Manages instance status, active runs, quick actions, and routing toggles.
/// Wired to real API endpoints for pause/resume/kill-switch/commands.
@MainActor
final class ControlViewModel: ObservableObject {

    // MARK: - Instance State

    @Published var instances: [Instance] = []
    @Published var selectedInstance: Instance?
    @Published var loadState: LoadState = .idle

    // MARK: - Active Runs

    @Published var activeRuns: [ActiveRun] = []

    // MARK: - Commands

    @Published var recentCommands: [CommandResponse] = []

    // MARK: - Routing Toggles

    @Published var routeToInbox: Bool = true
    @Published var routeToTelegram: Bool = false
    @Published var routeToEmail: Bool = false
    @Published var structuredMode: Bool = true

    // MARK: - Confirmation State

    @Published var pendingAction: ConfirmableAction? = nil

    // MARK: - Action In Progress

    @Published var actionInProgress: Bool = false
    @Published var actionError: String? = nil
    @Published var actionSuccess: String? = nil

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
            // Refresh selected instance from server
            if let selected = selectedInstance {
                await refreshInstance(selected.id)
            }
            // Load recent commands
            await loadRecentCommands()
            loadState = .loaded
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    func refreshInstance(_ id: UUID) async {
        do {
            let fresh = try await APIService.shared.fetchInstanceDetail(instanceID: id)
            if let index = instances.firstIndex(where: { $0.id == id }) {
                instances[index] = fresh
            }
            if selectedInstance?.id == id {
                selectedInstance = fresh
            }
        } catch {
            // Use stale data on refresh failure
        }
    }

    func loadRecentCommands() async {
        guard let instanceID = selectedInstance?.id else { return }
        do {
            recentCommands = try await APIService.shared.fetchCommands(instanceID: instanceID)
        } catch {
            // Silently fail — commands are supplementary
        }
    }

    // MARK: - Quick Actions

    func pauseInstance() {
        pendingAction = .pause
    }

    func resumeInstance() async {
        guard let instance = selectedInstance else { return }
        actionInProgress = true
        actionError = nil

        do {
            _ = try await APIService.shared.resumeInstance(instanceID: instance.id)
            Haptics.success()
            await refreshInstance(instance.id)
            actionSuccess = "Instance resumed"
        } catch {
            actionError = error.localizedDescription
        }

        actionInProgress = false
        clearSuccessAfterDelay()
    }

    func triggerKillSwitch() {
        pendingAction = .killSwitch
    }

    func testRun() async {
        guard let instance = selectedInstance else { return }
        Haptics.success()

        // Create a local active run for UI feedback
        let run = ActiveRun(
            id: UUID(),
            skillName: "connectivity_test",
            agentName: "system",
            startedAt: Date(),
            progress: 0.0,
            status: .running
        )
        activeRuns.insert(run, at: 0)

        // Send test_run command via API
        do {
            _ = try await APIService.shared.sendCommand(
                instanceID: instance.id,
                commandType: "test_run",
                reason: "user_action"
            )
        } catch {
            // Test run is best-effort; still show local progress
        }

        simulateProgress(for: run.id)
    }

    func stopRun(_ run: ActiveRun) {
        pendingAction = .stopRun(run)
    }

    func confirmAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil

        Task {
            switch action {
            case .pause:
                await performPause()
            case .killSwitch:
                await performKillSwitch()
            case .stopRun(let run):
                await performStopRun(run)
            }
        }
    }

    // MARK: - API-Backed Actions

    private func performPause() async {
        guard let instance = selectedInstance else { return }
        actionInProgress = true
        actionError = nil

        do {
            _ = try await APIService.shared.pauseInstance(instanceID: instance.id)
            Haptics.warning()
            await refreshInstance(instance.id)
            actionSuccess = "Instance paused"
        } catch {
            actionError = error.localizedDescription
        }

        actionInProgress = false
        clearSuccessAfterDelay()
    }

    private func performKillSwitch() async {
        guard let instance = selectedInstance else { return }
        actionInProgress = true
        actionError = nil

        do {
            _ = try await APIService.shared.killSwitch(instanceID: instance.id)
            Haptics.destructive()
            await refreshInstance(instance.id)
            actionSuccess = "Kill switch activated"
        } catch {
            actionError = error.localizedDescription
        }

        actionInProgress = false
        clearSuccessAfterDelay()
    }

    private func performStopRun(_ run: ActiveRun) async {
        guard let instance = selectedInstance else { return }
        Haptics.destructive()

        if let index = activeRuns.firstIndex(where: { $0.id == run.id }) {
            activeRuns[index].status = .stopping
        }

        // Send stop command via command channel
        do {
            _ = try await APIService.shared.sendCommand(
                instanceID: instance.id,
                commandType: "stop_run",
                payload: ["skill_name": run.skillName],
                reason: "user_action"
            )
        } catch {
            // Best-effort
        }

        // Remove after a delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        activeRuns.removeAll { $0.id == run.id }
    }

    // MARK: - Helpers

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

    private func clearSuccessAfterDelay() {
        guard actionSuccess != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.actionSuccess = nil
        }
    }

    var isPaused: Bool {
        selectedInstance?.mode == .paused || selectedInstance?.mode == .safe
    }
}
