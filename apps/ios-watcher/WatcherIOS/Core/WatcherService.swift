import Foundation

@MainActor
protocol WatcherServing {
    func fetchThreads(configuration: WatcherConfiguration, limit: Int) async throws -> [ThreadSummary]
    func fetchThreadDetail(threadID: String, configuration: WatcherConfiguration) async throws -> ThreadDetail
    func fetchThreadEvents(threadID: String, configuration: WatcherConfiguration, limit: Int) async throws -> [ThreadEvent]
}

@MainActor
protocol URLSessioning {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessioning {}

enum WatcherAPIError: LocalizedError {
    case invalidURL
    case requestFailed(statusCode: Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Watcher server URL."
        case let .requestFailed(statusCode):
            return "Watcher API request failed with status \(statusCode)."
        case .decodingFailed:
            return "Unable to decode Watcher response payload."
        }
    }
}

final class WatcherAPIClient: WatcherServing {
    private let session: URLSessioning
    private let decoder: JSONDecoder

    init(session: URLSessioning = URLSession.shared) {
        self.session = session

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func fetchThreads(configuration: WatcherConfiguration, limit: Int = 100) async throws -> [ThreadSummary] {
        let query = [URLQueryItem(name: "limit", value: String(limit))]
        let request = try makeRequest(configuration: configuration, path: "/threads", queryItems: query)
        return try await execute(request)
    }

    func fetchThreadDetail(threadID: String, configuration: WatcherConfiguration) async throws -> ThreadDetail {
        let request = try makeRequest(configuration: configuration, path: "/threads/\(threadID)")
        return try await execute(request)
    }

    func fetchThreadEvents(
        threadID: String,
        configuration: WatcherConfiguration,
        limit: Int = 300
    ) async throws -> [ThreadEvent] {
        let query = [URLQueryItem(name: "limit", value: String(limit))]
        let request = try makeRequest(
            configuration: configuration,
            path: "/threads/\(threadID)/events",
            queryItems: query
        )
        return try await execute(request)
    }

    private func makeRequest(
        configuration: WatcherConfiguration,
        path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        guard let url = configuration.apiURL(path: path, queryItems: queryItems) else {
            throw WatcherAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        if let token = configuration.authToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Watcher-Token")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func execute<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WatcherAPIError.requestFailed(statusCode: -1)
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw WatcherAPIError.requestFailed(statusCode: httpResponse.statusCode)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw WatcherAPIError.decodingFailed
        }
    }
}

extension WatcherConfiguration {
    func apiURL(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false)
        var mergedPath = components?.path.removingTrailingSlash ?? ""
        mergedPath += "/api/v1\(path)"
        components?.path = mergedPath
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        return components?.url
    }

    func webSocketURL() -> URL? {
        guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        switch components.scheme?.lowercased() {
        case "https":
            components.scheme = "wss"
        case "http":
            components.scheme = "ws"
        default:
            return nil
        }

        var mergedPath = components.path.removingTrailingSlash
        mergedPath += "/ws/v1/threads"
        components.path = mergedPath

        if let token = authToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            components.queryItems = [URLQueryItem(name: "token", value: token)]
        }

        return components.url
    }
}

private extension String {
    var removingTrailingSlash: String {
        if self == "/" {
            return ""
        }
        guard hasSuffix("/"), count > 1 else {
            return self
        }
        return String(dropLast())
    }
}
