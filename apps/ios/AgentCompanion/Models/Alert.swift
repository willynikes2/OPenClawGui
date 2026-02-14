import Foundation

/// A security detector alert linked to an event.
struct SecurityAlert: Codable, Identifiable, Equatable {
    let id: UUID
    let eventID: UUID
    let detectorName: String
    let severity: Severity
    let explanation: String
    let recommendedAction: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case detectorName = "detector_name"
        case severity, explanation
        case recommendedAction = "recommended_action"
        case createdAt = "created_at"
    }
}
