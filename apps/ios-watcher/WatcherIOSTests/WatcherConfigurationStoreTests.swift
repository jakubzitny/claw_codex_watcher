import XCTest
@testable import WatcherIOS

final class WatcherConfigurationStoreTests: XCTestCase {
    func testNormalizeServerURLAcceptsBareHostAndStripsWatcherPaths() {
        let store = WatcherConfigurationStore(defaults: makeDefaults())

        let normalized = store.normalizeServerURL(from: "127.0.0.1:18000/api/v1")

        XCTAssertEqual(normalized?.absoluteString, "http://127.0.0.1:18000")
    }

    func testSaveAndLoadRoundTrip() {
        let defaults = makeDefaults()
        let store = WatcherConfigurationStore(defaults: defaults)

        let configuration = WatcherConfiguration(
            serverURL: URL(string: "https://watcher.example.com/")!,
            authToken: "  token-123  "
        )

        store.save(configuration)
        let loaded = store.load()

        XCTAssertEqual(loaded.serverURL.absoluteString, "https://watcher.example.com")
        XCTAssertEqual(loaded.authToken, "token-123")
    }

    func testLoadFallsBackToDefaultWhenNoSettings() {
        let defaults = makeDefaults()
        let store = WatcherConfigurationStore(defaults: defaults)

        let loaded = store.load()

        XCTAssertEqual(loaded, .default)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "WatcherConfigurationStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
