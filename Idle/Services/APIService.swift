import Foundation
import Combine

class APIService: ObservableObject {
    static let shared = APIService()
    static var baseURL: String { Secrets.apiBaseURL }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Generic Request
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
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Children
    func getChildren(token: String) async throws -> [ChildProfile] {
        let response: APIResponse<[ChildProfile]> = try await request(endpoint: "/api/children", token: token)
        guard let children = response.data else { throw APIError.noData }
        return children
    }

    func createChild(profile: ChildProfile, token: String) async throws -> ChildProfile {
        let response: APIResponse<ChildProfile> = try await request(endpoint: "/api/children", method: "POST", body: profile, token: token)
        guard let child = response.data else { throw APIError.noData }
        return child
    }

    func updateChild(childId: String, profile: ChildProfile, token: String) async throws -> ChildProfile {
        let response: APIResponse<ChildProfile> = try await request(endpoint: "/api/children/\(childId)", method: "PUT", body: profile, token: token)
        guard let child = response.data else { throw APIError.noData }
        return child
    }

    // MARK: - Stories
    func getStories(childId: String, token: String? = nil) async throws -> [Story] {
        let tok = token ?? UserDefaults.standard.string(forKey: "accessToken")
        let response: APIResponse<[Story]> = try await request(endpoint: "/api/stories/child/\(childId)", token: tok)
        guard let stories = response.data else { throw APIError.noData }
        return stories
    }

    func generateStory(config: StoryConfig, token: String) async throws -> Story {
        let response: APIResponse<Story> = try await request(endpoint: "/api/generate/story", method: "POST", body: config, token: token)
        guard let story = response.data else { throw APIError.noData }
        return story
    }

    // MARK: - Vitals
    func postVitals(vitals: Vitals, token: String) async throws {
        let _: APIResponse<String> = try await request(endpoint: "/api/vitals/child/\(vitals.childId)", method: "POST", body: vitals, token: token)
    }

    func getStatistics(childId: String, token: String) async throws -> ChildStatistics {
        let response: APIResponse<ChildStatistics> = try await request(endpoint: "/api/statistics/child/\(childId)", token: token)
        guard let stats = response.data else { throw APIError.noData }
        return stats
    }
}

// MARK: - Story Configuration
struct StoryConfig: Codable {
    let childId: String
    let themes: [String]
    let initialState: InitialState
    let parentPrompt: String?
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
