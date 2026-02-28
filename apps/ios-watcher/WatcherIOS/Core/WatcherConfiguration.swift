import Foundation

struct WatcherConfiguration: Codable, Equatable {
    var serverURL: URL
    var authToken: String?

    static let `default` = WatcherConfiguration(
        serverURL: URL(string: "http://127.0.0.1:18000")!,
        authToken: nil
    )

    func normalized() -> WatcherConfiguration {
        var copy = self
        copy.serverURL = copy.serverURL.removingTrailingSlash()
        if let authToken {
            let trimmed = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.authToken = trimmed.isEmpty ? nil : trimmed
        }
        return copy
    }
}

protocol WatcherConfigurationStoring {
    func load() -> WatcherConfiguration
    func save(_ configuration: WatcherConfiguration)
    func normalizeServerURL(from rawValue: String) -> URL?
}

final class WatcherConfigurationStore: WatcherConfigurationStoring {
    private enum Keys {
        static let serverURL = "watcher.serverURL"
        static let authToken = "watcher.authToken"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> WatcherConfiguration {
        let storedServerURL = defaults.string(forKey: Keys.serverURL)
        let storedToken = defaults.string(forKey: Keys.authToken)

        let normalizedURL = storedServerURL
            .flatMap { normalizeServerURL(from: $0) }
            ?? WatcherConfiguration.default.serverURL

        let token = storedToken?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        return WatcherConfiguration(serverURL: normalizedURL, authToken: token)
    }

    func save(_ configuration: WatcherConfiguration) {
        let normalized = configuration.normalized()
        defaults.set(normalized.serverURL.absoluteString, forKey: Keys.serverURL)
        defaults.set(normalized.authToken, forKey: Keys.authToken)
    }

    func normalizeServerURL(from rawValue: String) -> URL? {
        var text = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }

        if !text.contains("://") {
            text = "http://\(text)"
        }

        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        components.fragment = nil
        components.query = nil

        var path = components.path
        if path.hasSuffix("/api/v1") {
            path = String(path.dropLast("/api/v1".count))
        }
        if path.hasSuffix("/ws/v1/threads") {
            path = String(path.dropLast("/ws/v1/threads".count))
        }

        path = path.removingTrailingSlash
        components.path = path

        guard let url = components.url else {
            return nil
        }
        return url.removingTrailingSlash()
    }
}

private extension URL {
    func removingTrailingSlash() -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        components.path = components.path.removingTrailingSlash
        return components.url ?? self
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

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
