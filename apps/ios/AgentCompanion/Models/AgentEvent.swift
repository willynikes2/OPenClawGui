import Foundation

/// An agent output event from the backend.
struct AgentEvent: Codable, Identifiable, Equatable {
    let id: UUID
    let instanceID: UUID
    let sourceType: SourceType
    let agentName: String
    let skillName: String
    let timestamp: Date
    let title: String
    let bodyStructuredJSON: [String: AnyCodable]?
    let tags: [String]?
    let severity: Severity
    let piiRedacted: Bool
    let createdAt: Date

    /// Only present in detail responses (decrypted server-side).
    var bodyRaw: String?

    /// Local-only state
    var isRead: Bool = false

    enum CodingKeys: String, CodingKey {
        case id
        case instanceID = "instance_id"
        case sourceType = "source_type"
        case agentName = "agent_name"
        case skillName = "skill_name"
        case timestamp, title
        case bodyStructuredJSON = "body_structured_json"
        case tags, severity
        case piiRedacted = "pii_redacted"
        case createdAt = "created_at"
        case bodyRaw = "body_raw"
    }

    static func == (lhs: AgentEvent, rhs: AgentEvent) -> Bool {
        lhs.id == rhs.id
    }
}

enum SourceType: String, Codable {
    case gateway, skill, telegram, sensor
}

/// Type-erased Codable for structured JSON.
struct AnyCodable: Codable, Equatable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let string as String: try container.encode(string)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let bool as Bool: try container.encode(bool)
        case let dict as [String: AnyCodable]: try container.encode(dict)
        case let array as [AnyCodable]: try container.encode(array)
        default: try container.encodeNil()
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }
}
