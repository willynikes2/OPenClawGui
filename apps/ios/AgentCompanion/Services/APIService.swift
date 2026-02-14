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
