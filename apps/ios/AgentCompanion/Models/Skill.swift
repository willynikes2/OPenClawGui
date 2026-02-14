import Foundation
import SwiftUI

/// A skill observed or declared on an instance.
struct Skill: Codable, Identifiable, Equatable {
    let id: UUID
    let instanceID: UUID
    let name: String
    var trustStatus: TrustStatus
    let lastRun: Date?
    let createdAt: Date

    /// Local-only: observed behaviors for display
    var observedBehaviors: [String] = []

    enum CodingKeys: String, CodingKey {
        case id
        case instanceID = "instance_id"
        case name
        case trustStatus = "trust_status"
        case lastRun = "last_run"
        case createdAt = "created_at"
    }
}

enum TrustStatus: String, Codable, CaseIterable {
    case trusted
    case untrusted
    case unknown

    var label: LocalizedStringKey {
        switch self {
        case .trusted: "Trusted"
        case .untrusted: "Untrusted"
        case .unknown: "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .trusted: "checkmark.shield.fill"
        case .untrusted: "xmark.shield.fill"
        case .unknown: "questionmark.diamond.fill"
        }
    }

    var color: Color {
        switch self {
        case .trusted: AppColors.trusted
        case .untrusted: AppColors.untrusted
        case .unknown: AppColors.unknown
        }
    }
}
