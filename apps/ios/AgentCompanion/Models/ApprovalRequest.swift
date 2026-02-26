import Foundation

/// An approval request for a sensitive agent action.
struct ApprovalRequest: Codable, Identifiable, Equatable {
    let id: UUID
    let instanceId: UUID
    let threadId: UUID?
    let skillName: String
    let action: ApprovalActionType
    let summary: String
    let riskLevel: ApprovalRiskLevel
    let options: [String]?
    let evidence: [String: AnyCodable]?
    let status: ApprovalStatus
    let decidedBy: UUID?
    let decidedAt: Date?
    let decision: String?
    let expiresAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case instanceId = "instance_id"
        case threadId = "thread_id"
        case skillName = "skill_name"
        case action, summary
        case riskLevel = "risk_level"
        case options, evidence, status
        case decidedBy = "decided_by"
        case decidedAt = "decided_at"
        case decision
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }

    static func == (lhs: ApprovalRequest, rhs: ApprovalRequest) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status
    }

    var isExpired: Bool {
        Date() > expiresAt
    }

    var isPending: Bool {
        status == .pending && !isExpired
    }
}

enum ApprovalActionType: String, Codable {
    case sendEmail = "send_email"
    case execShell = "exec_shell"
    case accessSensitivePath = "access_sensitive_path"
    case newDomain = "new_domain"
    case bulkExport = "bulk_export"

    var displayName: String {
        switch self {
        case .sendEmail: return "Send Email"
        case .execShell: return "Execute Shell"
        case .accessSensitivePath: return "Access Sensitive Path"
        case .newDomain: return "New Domain Contact"
        case .bulkExport: return "Bulk Export"
        }
    }

    var icon: String {
        switch self {
        case .sendEmail: return "envelope.fill"
        case .execShell: return "terminal.fill"
        case .accessSensitivePath: return "lock.shield.fill"
        case .newDomain: return "globe"
        case .bulkExport: return "square.and.arrow.up.fill"
        }
    }
}

enum ApprovalRiskLevel: String, Codable {
    case warning
    case critical

    var displayName: String {
        switch self {
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
}

enum ApprovalStatus: String, Codable {
    case pending
    case approved
    case denied
    case expired
}
