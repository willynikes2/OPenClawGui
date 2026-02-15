import Foundation

/// API client for the AgentCompanion backend.
/// Handles authentication, request signing, and JSON decoding.
@MainActor
final class APIService: ObservableObject {
    static let shared = APIService()

    private let baseURL: URL
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    @Published var accessToken: String?

    private init() {
        // Configurable via environment or settings — default to localhost for dev
        self.baseURL = URL(string: "http://localhost:8000/api/v1")!
    }

    // MARK: - Events

    func fetchEvents(
        instanceID: UUID? = nil,
        severity: Severity? = nil,
        skillName: String? = nil,
        agentName: String? = nil,
        cursor: String? = nil,
        limit: Int = 20
    ) async throws -> EventListResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("events"), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = [.init(name: "limit", value: String(limit))]

        if let instanceID { queryItems.append(.init(name: "instance_id", value: instanceID.uuidString)) }
        if let severity { queryItems.append(.init(name: "severity", value: severity.rawValue)) }
        if let skillName { queryItems.append(.init(name: "skill_name", value: skillName)) }
        if let agentName { queryItems.append(.init(name: "agent_name", value: agentName)) }
        if let cursor { queryItems.append(.init(name: "cursor", value: cursor)) }

        components.queryItems = queryItems

        return try await authenticatedRequest(url: components.url!)
    }

    func fetchEventDetail(eventID: UUID) async throws -> AgentEvent {
        let url = baseURL.appendingPathComponent("events/\(eventID.uuidString)")
        return try await authenticatedRequest(url: url)
    }

    // MARK: - Instances

    func fetchInstances() async throws -> [Instance] {
        let url = baseURL.appendingPathComponent("instances")
        return try await authenticatedRequest(url: url)
    }

    func fetchInstanceDetail(instanceID: UUID) async throws -> Instance {
        let url = baseURL.appendingPathComponent("instances/\(instanceID.uuidString)")
        return try await authenticatedRequest(url: url)
    }

    // MARK: - Containment (Control Tab)

    func pauseInstance(instanceID: UUID, reason: String = "user_action") async throws -> ContainmentResponse {
        let url = baseURL.appendingPathComponent("instances/\(instanceID.uuidString)/pause")
        let body = ContainmentRequest(reason: reason)
        return try await authenticatedPost(url: url, body: body)
    }

    func resumeInstance(instanceID: UUID) async throws -> ContainmentResponse {
        let url = baseURL.appendingPathComponent("instances/\(instanceID.uuidString)/resume")
        return try await authenticatedPost(url: url)
    }

    func killSwitch(instanceID: UUID, reason: String = "user_action") async throws -> ContainmentResponse {
        let url = baseURL.appendingPathComponent("instances/\(instanceID.uuidString)/kill-switch")
        let body = ContainmentRequest(reason: reason)
        return try await authenticatedPost(url: url, body: body)
    }

    // MARK: - Commands (Control Tab)

    func sendCommand(
        instanceID: UUID,
        commandType: String,
        payload: [String: String]? = nil,
        reason: String? = nil
    ) async throws -> CommandResponse {
        let url = baseURL.appendingPathComponent("instances/\(instanceID.uuidString)/commands")
        let body = CommandCreateRequest(
            commandType: commandType,
            payload: payload,
            reason: reason
        )
        return try await authenticatedPost(url: url, body: body)
    }

    func fetchCommands(instanceID: UUID, status: String? = nil) async throws -> [CommandResponse] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("instances/\(instanceID.uuidString)/commands"),
            resolvingAgainstBaseURL: false
        )!
        if let status {
            components.queryItems = [.init(name: "status", value: status)]
        }
        return try await authenticatedRequest(url: components.url!)
    }

    // MARK: - Alerts (Security Tab)

    func fetchAlerts(
        instanceID: UUID,
        severity: Severity? = nil,
        detector: String? = nil,
        limit: Int = 20,
        cursor: String? = nil
    ) async throws -> AlertListResponse {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("instances/\(instanceID.uuidString)/alerts"),
            resolvingAgainstBaseURL: false
        )!
        var queryItems: [URLQueryItem] = [.init(name: "limit", value: String(limit))]
        if let severity { queryItems.append(.init(name: "severity", value: severity.rawValue)) }
        if let detector { queryItems.append(.init(name: "detector", value: detector)) }
        if let cursor { queryItems.append(.init(name: "cursor", value: cursor)) }
        components.queryItems = queryItems
        return try await authenticatedRequest(url: components.url!)
    }

    func fetchRiskSummary(instanceID: UUID) async throws -> RiskSummaryResponse {
        let url = baseURL.appendingPathComponent("instances/\(instanceID.uuidString)/risk-summary")
        return try await authenticatedRequest(url: url)
    }

    // MARK: - Skills

    func fetchSkills(instanceID: UUID) async throws -> [SkillAPIResponse] {
        let url = baseURL.appendingPathComponent("instances/\(instanceID.uuidString)/skills")
        return try await authenticatedRequest(url: url)
    }

    func disableSkill(instanceID: UUID, skillName: String, reason: String = "user_action") async throws -> ContainmentResponse {
        let url = baseURL.appendingPathComponent("instances/\(instanceID.uuidString)/skills/\(skillName)/disable")
        let body = ContainmentRequest(reason: reason)
        return try await authenticatedPost(url: url, body: body)
    }

    // MARK: - Chat

    func fetchChatThreads(instanceId: UUID? = nil, limit: Int = 20) async throws -> [ChatThread] {
        var components = URLComponents(url: baseURL.appendingPathComponent("chat/threads"), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = [.init(name: "limit", value: String(limit))]
        if let instanceId { queryItems.append(.init(name: "instance_id", value: instanceId.uuidString)) }
        components.queryItems = queryItems
        return try await authenticatedRequest(url: components.url!)
    }

    func fetchChatThread(threadId: UUID) async throws -> ChatThreadDetail {
        let url = baseURL.appendingPathComponent("chat/thread/\(threadId.uuidString)")
        return try await authenticatedRequest(url: url)
    }

    func sendChatMessage(
        threadId: UUID? = nil,
        instanceId: UUID,
        content: String,
        attachedEventId: UUID? = nil,
        attachedAlertId: UUID? = nil
    ) async throws -> ChatSendResponse {
        let url = baseURL.appendingPathComponent("chat/send")
        let body = ChatSendRequest(
            threadId: threadId,
            instanceId: instanceId,
            content: content,
            attachedEventId: attachedEventId,
            attachedAlertId: attachedAlertId
        )
        return try await authenticatedPost(url: url, body: body)
    }

    func attachChatContext(
        threadId: UUID,
        eventId: UUID? = nil,
        alertId: UUID? = nil
    ) async throws -> ChatMessage {
        let url = baseURL.appendingPathComponent("chat/attach_context")
        let body = AttachContextAPIRequest(threadId: threadId, eventId: eventId, alertId: alertId)
        return try await authenticatedPost(url: url, body: body)
    }

    // MARK: - Networking

    private func authenticatedRequest<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(statusCode: http.statusCode, body: body)
        }

        return try decoder.decode(T.self, from: data)
    }

    private func authenticatedPost<T: Decodable>(url: URL, body: (any Encodable)? = nil) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(statusCode: http.statusCode, body: body)
        }

        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - Request Types

struct ContainmentRequest: Codable {
    let reason: String

    enum CodingKeys: String, CodingKey {
        case reason
    }
}

struct CommandCreateRequest: Codable {
    let commandType: String
    let payload: [String: String]?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case commandType = "command_type"
        case payload, reason
    }
}

struct ChatSendRequest: Codable {
    let threadId: UUID?
    let instanceId: UUID
    let content: String
    let attachedEventId: UUID?
    let attachedAlertId: UUID?

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case instanceId = "instance_id"
        case content
        case attachedEventId = "attached_event_id"
        case attachedAlertId = "attached_alert_id"
    }
}

struct AttachContextAPIRequest: Codable {
    let threadId: UUID
    let eventId: UUID?
    let alertId: UUID?

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case eventId = "event_id"
        case alertId = "alert_id"
    }
}

// MARK: - Response Types

struct EventListResponse: Codable {
    let events: [AgentEvent]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case events
        case nextCursor = "next_cursor"
    }
}

struct ContainmentResponse: Codable {
    let status: String
    let instanceId: UUID?
    let skillName: String?
    let tokenRevoked: Bool?
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case status
        case instanceId = "instance_id"
        case skillName = "skill_name"
        case tokenRevoked = "token_revoked"
        case timestamp
    }
}

struct CommandResponse: Codable, Identifiable {
    let id: UUID
    let instanceId: UUID
    let commandType: String
    let payload: [String: String]?
    let status: String
    let reason: String?
    let resultMessage: String?
    let createdAt: Date
    let acknowledgedAt: Date?
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case instanceId = "instance_id"
        case commandType = "command_type"
        case payload, status, reason
        case resultMessage = "result_message"
        case createdAt = "created_at"
        case acknowledgedAt = "acknowledged_at"
        case completedAt = "completed_at"
    }
}

struct AlertListResponse: Codable {
    let alerts: [SecurityAlertAPI]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case alerts
        case nextCursor = "next_cursor"
    }
}

struct SecurityAlertAPI: Codable, Identifiable {
    let id: UUID
    let eventId: UUID
    let instanceId: UUID
    let detectorName: String
    let skillName: String
    let severity: Severity
    let explanation: String
    let recommendedAction: String
    let evidence: [String: AnyCodable]?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case instanceId = "instance_id"
        case detectorName = "detector_name"
        case skillName = "skill_name"
        case severity, explanation
        case recommendedAction = "recommended_action"
        case evidence
        case createdAt = "created_at"
    }
}

struct RiskSummaryResponse: Codable {
    let totalAlertsToday: Int
    let mostCommonDetector: String?
    let lastCriticalTimestamp: Date?
    let status: String

    enum CodingKeys: String, CodingKey {
        case totalAlertsToday = "total_alerts_today"
        case mostCommonDetector = "most_common_detector"
        case lastCriticalTimestamp = "last_critical_timestamp"
        case status
    }
}

struct SkillAPIResponse: Codable, Identifiable {
    let id: UUID
    let name: String
    let trustStatus: String
    let lastRun: Date?
    let instanceId: UUID
    let createdAt: Date
    let observedBehaviors: [String]

    enum CodingKeys: String, CodingKey {
        case id, name
        case trustStatus = "trust_status"
        case lastRun = "last_run"
        case instanceId = "instance_id"
        case createdAt = "created_at"
        case observedBehaviors = "observed_behaviors"
    }
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return String(localized: "Invalid server response.")
        case .httpError(let code, _):
            return String(localized: "Server error (\(code)).")
        }
    }
}
