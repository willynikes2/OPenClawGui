import Foundation

/// A message in a chat thread.
struct ChatMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let threadId: UUID
    let messageType: ChatMessageType
    let senderType: ChatSenderType
    let content: String?
    let structuredJson: [String: AnyCodable]?
    let routingPlanId: UUID?
    let correlationId: UUID?
    let eventId: UUID?
    let alertId: UUID?
    let toolUsage: [String: AnyCodable]?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case threadId = "thread_id"
        case messageType = "message_type"
        case senderType = "sender_type"
        case content
        case structuredJson = "structured_json"
        case routingPlanId = "routing_plan_id"
        case correlationId = "correlation_id"
        case eventId = "event_id"
        case alertId = "alert_id"
        case toolUsage = "tool_usage"
        case createdAt = "created_at"
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

enum ChatMessageType: String, Codable {
    case userMessage = "user_message"
    case assistantMessage = "assistant_message"
    case agentMessage = "agent_message"
    case structuredCardMessage = "structured_card_message"
    case systemMessage = "system_message"
    case approvalRequest = "approval_request"
}

enum ChatSenderType: String, Codable {
    case user
    case assistant
    case agent
    case system
}
