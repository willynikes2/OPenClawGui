import Foundation

/// A chat conversation thread.
struct ChatThread: Codable, Identifiable, Equatable {
    let id: UUID
    let instanceId: UUID
    let title: String?
    let createdAt: Date
    let updatedAt: Date
    let lastMessage: ChatMessage?

    enum CodingKeys: String, CodingKey {
        case id
        case instanceId = "instance_id"
        case title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastMessage = "last_message"
    }

    static func == (lhs: ChatThread, rhs: ChatThread) -> Bool {
        lhs.id == rhs.id
    }
}

/// Thread detail with all messages.
struct ChatThreadDetail: Codable, Identifiable {
    let id: UUID
    let instanceId: UUID
    let title: String?
    let createdAt: Date
    let updatedAt: Date
    let messages: [ChatMessage]

    enum CodingKeys: String, CodingKey {
        case id
        case instanceId = "instance_id"
        case title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case messages
    }
}

/// Routing plan summary returned from /chat/send.
struct RoutingPlanResponse: Codable {
    let id: UUID
    let threadId: UUID
    let instanceId: UUID
    let intent: String
    let targets: [AnyCodable]?
    let requiresApproval: Bool
    let safetyPolicy: String
    let notes: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case threadId = "thread_id"
        case instanceId = "instance_id"
        case intent
        case targets
        case requiresApproval = "requires_approval"
        case safetyPolicy = "safety_policy"
        case notes
        case createdAt = "created_at"
    }
}

/// Response from POST /chat/send.
struct ChatSendResponse: Codable {
    let threadId: UUID
    let userMessage: ChatMessage
    let routingPlan: RoutingPlanResponse
    let systemMessage: ChatMessage?

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case userMessage = "user_message"
        case routingPlan = "routing_plan"
        case systemMessage = "system_message"
    }
}
