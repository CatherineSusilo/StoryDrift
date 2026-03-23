import Foundation
import Combine

class APIService: ObservableObject {
    static let shared = APIService()
    static var baseURL: String { Secrets.apiBaseURL }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Generic Request
    // Decodes T directly from the response — the backend returns raw objects/arrays, not wrapped in APIResponse
    func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Encodable? = nil,
        token: String? = nil
    ) async throws -> T {
        guard let url = URL(string: "\(Self.baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? "nil"
            print("❌ HTTP \(httpResponse.statusCode) from \(endpoint): \(raw)")
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)

            // Try ISO8601 with fractional seconds (Prisma/MongoDB default: "2026-03-22T12:00:00.000Z")
            let withMs = ISO8601DateFormatter()
            withMs.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withMs.date(from: str) { return date }

            // Fallback: ISO8601 without fractional seconds
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: str) { return date }

            throw DecodingError.dataCorruptedError(in: container,
                debugDescription: "Cannot decode date: \(str)")
        }
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Children
    func getChildren(token: String) async throws -> [Child] {
        return try await request(endpoint: "/api/children", token: token)
    }

    func createChild(request body: CreateChildRequest, token: String) async throws -> Child {
        return try await request(endpoint: "/api/children", method: "POST", body: body, token: token)
    }

    func updateChild(childId: String, body: UpdateChildRequest, token: String) async throws -> Child {
        return try await request(endpoint: "/api/children/\(childId)", method: "PATCH", body: body, token: token)
    }

    func deleteChild(childId: String, token: String) async throws {
        let _: DeleteResponse = try await request(endpoint: "/api/children/\(childId)", method: "DELETE", token: token)
    }

    // MARK: - Stories
    func getStories(childId: String, token: String? = nil) async throws -> [Story] {
        let tok = token ?? UserDefaults.standard.string(forKey: "accessToken")
        let response: PaginatedResponse<Story> = try await request(endpoint: "/api/stories/child/\(childId)", token: tok)
        return response.data
    }

    func generateStory(config: StoryConfig, token: String) async throws -> Story {
        // Step 1: Generate story text + image prompts via Gemini
        let generateBody: [String: Any] = ["profile": [
            "childId": config.childId,
            "name": config.name,
            "age": config.age,
            "storytellingTone": config.storytellingTone,
            "parentPrompt": config.parentPrompt,
            "initialState": config.initialState
        ]]

        guard let url = URL(string: "\(Self.baseURL)/api/generate/story") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: generateBody)

        let (genData, genResp) = try await URLSession.shared.data(for: req)
        if let http = genResp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let raw = String(data: genData, encoding: .utf8) ?? "nil"
            print("❌ HTTP \(http.statusCode) from /api/generate/story: \(raw)")
            throw APIError.httpError(statusCode: http.statusCode)
        }

        guard let genJson = try JSONSerialization.jsonObject(with: genData) as? [String: Any],
              let storyText = genJson["story"] as? String else {
            throw APIError.invalidResponse
        }

        let modelUsed = genJson["modelUsed"] as? String ?? "gemini"
        print("✅ Story generated (\(storyText.count) chars), saving to backend...")

        // Step 2: Save the story session to the backend
        let saveBody: [String: Any] = [
            "childId": config.childId,
            "storyTitle": "Bedtime Story",
            "storyContent": storyText,
            "parentPrompt": config.parentPrompt,
            "storytellingTone": config.storytellingTone,
            "initialState": config.initialState,
            "initialDriftScore": 0,
            "modelUsed": modelUsed
        ]

        let story: Story = try await request(endpoint: "/api/stories", method: "POST", body: AnyCodable(saveBody), token: token)
        return story
    }

    // MARK: - Vitals
    func postVitals(vitals: Vitals, token: String) async throws {
        let _: EmptyResponse = try await request(endpoint: "/api/vitals/child/\(vitals.childId)", method: "POST", body: vitals, token: token)
    }

    func getStatistics(childId: String, token: String) async throws -> ChildStatistics {
        return try await request(endpoint: "/api/statistics/stories/\(childId)", token: token)
    }

    func getSleepStatistics(childId: String, token: String) async throws -> SleepStatisticsResponse {
        return try await request(endpoint: "/api/statistics/sleep/\(childId)", token: token)
    }
}

// MARK: - Story Configuration
struct StoryConfig: Codable {
    let childId: String
    let name: String
    let age: Int
    let storytellingTone: String
    let parentPrompt: String
    let initialState: String
}

// MARK: - API Errors
enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL:          return "Invalid URL"
        case .invalidResponse:     return "Invalid response from server"
        case .httpError(let code): return "HTTP error: \(code)"
        case .noData:              return "No data received"
        }
    }
}

/// Wraps a [String: Any] dictionary so it can be passed as Encodable to the generic request()
struct AnyCodable: Encodable {
    private let value: [String: Any]
    init(_ value: [String: Any]) { self.value = value }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, val) in value {
            let k = AnyCodingKey(key)
            switch val {
            case let v as String:  try container.encode(v, forKey: k)
            case let v as Int:     try container.encode(v, forKey: k)
            case let v as Double:  try container.encode(v, forKey: k)
            case let v as Bool:    try container.encode(v, forKey: k)
            case let v as [String]: try container.encode(v, forKey: k)
            default: break
            }
        }
    }
}
struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { self.stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
