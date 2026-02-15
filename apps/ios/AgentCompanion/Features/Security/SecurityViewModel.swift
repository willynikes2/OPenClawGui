import Foundation
import SwiftUI

/// View model for the Security tab.
/// Manages risk summary, alerts list, skill trust, and detector settings.
@MainActor
final class SecurityViewModel: ObservableObject {

    // MARK: - Instance

    @Published var instances: [Instance] = []
    @Published var selectedInstance: Instance?

    // MARK: - Alerts

    @Published var alerts: [SecurityAlert] = []
    @Published var alertFilter: AlertFilter = .all
    @Published var loadState: LoadState = .idle

    // MARK: - Skills

    @Published var skills: [Skill] = []
    @Published var pendingSkillAction: SkillAction? = nil

    // MARK: - Detector Settings

    @Published var detectors: [DetectorConfig] = DetectorConfig.defaultDetectors

    enum LoadState {
        case idle, loading, loaded, error(String)
    }

    enum AlertFilter: String, CaseIterable, CustomStringConvertible, Hashable {
        case all = "All"
        case critical = "Critical"
        case warning = "Warning"

        var description: String { rawValue }
    }

    struct SkillAction: Identifiable {
        let id = UUID()
        let skill: Skill
        let action: SkillActionType
    }

    enum SkillActionType {
        case disable, allowlist
    }

    // MARK: - Risk Summary Computed

    var alertsToday: Int {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return filteredAlerts.filter { $0.createdAt >= startOfDay }.count
    }

    var mostCommonDetector: String? {
        let todayAlerts = alerts.filter {
            $0.createdAt >= Calendar.current.startOfDay(for: Date())
        }
        guard !todayAlerts.isEmpty else { return nil }

        let counts = Dictionary(grouping: todayAlerts, by: \.detectorName)
            .mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key
    }

    var lastCriticalDate: Date? {
        alerts.filter { $0.severity == .critical }
            .map(\.createdAt)
            .max()
    }

    var filteredAlerts: [SecurityAlert] {
        switch alertFilter {
        case .all: alerts
        case .critical: alerts.filter { $0.severity == .critical }
        case .warning: alerts.filter { $0.severity == .warn }
        }
    }

    var trustedSkills: [Skill] {
        skills.filter { $0.trustStatus == .trusted }
    }

    var untrustedSkills: [Skill] {
        skills.filter { $0.trustStatus != .trusted }
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
            // In production: fetch alerts and skills from API
            loadState = .loaded

            // Update widget with alert count
            WidgetDataService.update(
                alertCount: alertsToday,
                instanceHealth: selectedInstance?.health.rawValue ?? "unknown"
            )
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    // MARK: - Skill Actions

    func requestDisableSkill(_ skill: Skill) {
        pendingSkillAction = SkillAction(skill: skill, action: .disable)
    }

    func requestAllowlistSkill(_ skill: Skill) {
        pendingSkillAction = SkillAction(skill: skill, action: .allowlist)
    }

    func confirmSkillAction() {
        guard let action = pendingSkillAction else { return }
        if let index = skills.firstIndex(where: { $0.id == action.skill.id }) {
            switch action.action {
            case .disable:
                Haptics.destructive()
                skills[index].trustStatus = .untrusted
            case .allowlist:
                Haptics.success()
                skills[index].trustStatus = .trusted
            }
        }
        pendingSkillAction = nil
    }

    // MARK: - Detector Settings

    func toggleDetector(id: UUID) {
        guard let index = detectors.firstIndex(where: { $0.id == id }) else { return }
        if detectors[index].isRequired {
            // Cannot disable required detectors
            Haptics.warning()
            return
        }
        detectors[index].isEnabled.toggle()
        Haptics.selection()
    }

    func setSensitivity(id: UUID, level: DetectorSensitivity) {
        guard let index = detectors.firstIndex(where: { $0.id == id }) else { return }
        detectors[index].sensitivity = level
        Haptics.selection()
    }
}

// MARK: - Detector Config

struct DetectorConfig: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    var isEnabled: Bool
    let isRequired: Bool  // Some must remain on
    var sensitivity: DetectorSensitivity

    static let defaultDetectors: [DetectorConfig] = [
        DetectorConfig(
            name: "New Domain Contacted",
            icon: "globe",
            isEnabled: true, isRequired: true,
            sensitivity: .medium
        ),
        DetectorConfig(
            name: "Shell Spawned",
            icon: "terminal",
            isEnabled: true, isRequired: true,
            sensitivity: .medium
        ),
        DetectorConfig(
            name: "Sensitive Path Access",
            icon: "folder.badge.questionmark",
            isEnabled: true, isRequired: false,
            sensitivity: .medium
        ),
        DetectorConfig(
            name: "High-Frequency Loop",
            icon: "arrow.2.squarepath",
            isEnabled: true, isRequired: false,
            sensitivity: .medium
        ),
        DetectorConfig(
            name: "Unexpected Secret Pattern",
            icon: "key.fill",
            isEnabled: true, isRequired: true,
            sensitivity: .high
        ),
    ]
}

enum DetectorSensitivity: String, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Med"
    case high = "High"

    var id: String { rawValue }
}
