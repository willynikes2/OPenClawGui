import Foundation

/// Represents an in-progress agent run on an instance.
struct ActiveRun: Identifiable, Equatable {
    let id: UUID
    let skillName: String
    let agentName: String
    let startedAt: Date
    var progress: Double  // 0.0 ... 1.0
    var status: RunStatus

    enum RunStatus: String {
        case running, stopping, completed
    }
}
