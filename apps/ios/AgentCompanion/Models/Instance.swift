import Foundation
import SwiftUI

/// A Claw deployment instance.
struct Instance: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let mode: InstanceMode
    let health: HealthStatus
    let lastSeen: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, mode, health
        case lastSeen = "last_seen"
        case createdAt = "created_at"
    }
}

enum InstanceMode: String, Codable {
    case active, paused, safe
}

enum HealthStatus: String, Codable {
    case ok, degraded, offline

    var label: String {
        switch self {
        case .ok: String(localized: "OK")
        case .degraded: String(localized: "Degraded")
        case .offline: String(localized: "Offline")
        }
    }

    var dotColor: Color {
        switch self {
        case .ok: AppColors.healthOK
        case .degraded: AppColors.healthDegraded
        case .offline: AppColors.healthOffline
        }
    }
}
