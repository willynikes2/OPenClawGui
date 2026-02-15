import Foundation
import SwiftUI

/// View model for the Settings tab.
/// Manages account, privacy, notification, voice, and advanced settings.
@MainActor
final class SettingsViewModel: ObservableObject {

    // MARK: - Account

    @Published var userEmail: String = ""
    @Published var devices: [PairedDevice] = []

    // MARK: - Instances

    @Published var instances: [Instance] = []

    // MARK: - Privacy & Retention

    @Published var dataRetention: DataRetention = .thirtyDays
    @Published var redactPII: Bool = true
    @Published var storeRawOutput: Bool = false
    @Published var storeTelemetry: Bool = true
    @Published var showPIIWarning: Bool = false

    // MARK: - Notifications

    @Published var notificationsEnabled: Bool = true
    @Published var notifyCritical: Bool = true
    @Published var notifyWarning: Bool = true
    @Published var notifyInfo: Bool = false
    @Published var quietHoursEnabled: Bool = false
    @Published var quietHoursStart: Date = Calendar.current.date(from: DateComponents(hour: 22)) ?? Date()
    @Published var quietHoursEnd: Date = Calendar.current.date(from: DateComponents(hour: 7)) ?? Date()

    // MARK: - Voice & Playback

    @Published var ttsRate: TTSRate = .normal
    @Published var autoPlayTTS: Bool = false

    // MARK: - Advanced

    @Published var cacheSize: String = "Calculating..."
    @Published var showClearCacheConfirmation: Bool = false
    @Published var showDeleteDataConfirmation: Bool = false
    @Published var showExportSheet: Bool = false

    // MARK: - Confirmation State

    @Published var pendingDestructiveAction: DestructiveSettingsAction? = nil

    // MARK: - Load

    func loadSettings() async {
        do {
            instances = try await APIService.shared.fetchInstances()
        } catch {
            // Fail silently — settings still functional with local state
        }
        calculateCacheSize()
    }

    // MARK: - PII Toggle

    func attemptDisablePII() {
        showPIIWarning = true
    }

    func confirmDisablePII() {
        redactPII = false
        showPIIWarning = false
        Haptics.warning()
    }

    // MARK: - Destructive Actions

    func requestDeleteData() {
        pendingDestructiveAction = .deleteAllData
    }

    func requestClearCache() {
        pendingDestructiveAction = .clearCache
    }

    func requestRevokeDevice(_ device: PairedDevice) {
        pendingDestructiveAction = .revokeDevice(device)
    }

    func confirmDestructiveAction() {
        guard let action = pendingDestructiveAction else { return }
        switch action {
        case .deleteAllData:
            Haptics.destructive()
            EventCacheService.shared.purgeAll()
            calculateCacheSize()
        case .clearCache:
            Haptics.destructive()
            EventCacheService.shared.purgeAll()
            calculateCacheSize()
        case .revokeDevice(let device):
            Haptics.destructive()
            devices.removeAll { $0.id == device.id }
        case .removeInstance(let instance):
            Haptics.destructive()
            instances.removeAll { $0.id == instance.id }
        }
        pendingDestructiveAction = nil
    }

    func requestRemoveInstance(_ instance: Instance) {
        pendingDestructiveAction = .removeInstance(instance)
    }

    // MARK: - Cache

    func calculateCacheSize() {
        let bytes = EventCacheService.shared.estimatedCacheSize()
        cacheSize = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: - Export

    func exportData() -> URL? {
        return EventCacheService.shared.exportAsJSON()
    }

    func exportLogs() -> URL? {
        // In production: gather app logs and write to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let logFile = tempDir.appendingPathComponent("agentcompanion_logs.txt")
        try? "AgentCompanion Logs\nExported: \(Date().ISO8601Format())\n\nNo logs available in MVP.".write(to: logFile, atomically: true, encoding: .utf8)
        return logFile
    }
}

// MARK: - Supporting Types

struct PairedDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let platform: String
    let lastSeen: Date?
    let isCurrent: Bool
}

enum DataRetention: String, CaseIterable, Identifiable {
    case sevenDays = "7 Days"
    case thirtyDays = "30 Days"
    case ninetyDays = "90 Days"
    case unlimited = "Unlimited"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .sevenDays: 7
        case .thirtyDays: 30
        case .ninetyDays: 90
        case .unlimited: nil
        }
    }

    var icon: String {
        switch self {
        case .sevenDays: "7.circle"
        case .thirtyDays: "30.circle"
        case .ninetyDays: "90.circle"
        case .unlimited: "infinity.circle"
        }
    }
}

enum TTSRate: String, CaseIterable, Identifiable {
    case slow = "Slow"
    case normal = "Normal"
    case fast = "Fast"

    var id: String { rawValue }

    var rate: Float {
        switch self {
        case .slow: 0.4
        case .normal: 0.5
        case .fast: 0.6
        }
    }
}

enum DestructiveSettingsAction: Identifiable {
    case deleteAllData
    case clearCache
    case revokeDevice(PairedDevice)
    case removeInstance(Instance)

    var id: String {
        switch self {
        case .deleteAllData: "deleteAll"
        case .clearCache: "clearCache"
        case .revokeDevice(let d): "revoke-\(d.id)"
        case .removeInstance(let i): "remove-\(i.id)"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .deleteAllData: "Delete All Data"
        case .clearCache: "Clear Cache"
        case .revokeDevice: "Revoke Device"
        case .removeInstance: "Remove Instance"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .deleteAllData:
            "This will permanently delete all cached events, alerts, and local data. This cannot be undone."
        case .clearCache:
            "This will clear all locally cached events. They can be re-fetched from the server."
        case .revokeDevice(let device):
            "This will revoke trust for \(device.name). It will no longer receive push notifications or sync data."
        case .removeInstance(let instance):
            "This will remove \(instance.name) and all its associated data from this device."
        }
    }

    var buttonLabel: LocalizedStringKey {
        switch self {
        case .deleteAllData: "Delete Everything"
        case .clearCache: "Clear Cache"
        case .revokeDevice: "Revoke"
        case .removeInstance: "Remove"
        }
    }
}
