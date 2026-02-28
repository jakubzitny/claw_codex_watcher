import Foundation

@MainActor
final class AppContainer {
    static let shared = AppContainer()

    let configurationStore: WatcherConfigurationStore
    let store: WatcherStore

    private init() {
        configurationStore = WatcherConfigurationStore()
        store = WatcherStore(
            configurationStore: configurationStore,
            service: WatcherAPIClient(),
            stream: ThreadsWebSocketClient()
        )
    }
}
