import Foundation

protocol ThreadsStreaming: AnyObject {
    func connect(
        configuration: WatcherConfiguration,
        onSnapshot: @escaping @Sendable ([ThreadSummary]) -> Void,
        onDisconnect: @escaping @Sendable (String) -> Void
    )
    func disconnect()
}

final class ThreadsWebSocketClient: NSObject, ThreadsStreaming {
    private let session: URLSession

    private var webSocketTask: URLSessionWebSocketTask?
    private var onSnapshot: (@Sendable ([ThreadSummary]) -> Void)?
    private var onDisconnect: (@Sendable (String) -> Void)?
    private var isActive = false

    override init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration)
        super.init()
    }

    func connect(
        configuration: WatcherConfiguration,
        onSnapshot: @escaping @Sendable ([ThreadSummary]) -> Void,
        onDisconnect: @escaping @Sendable (String) -> Void
    ) {
        disconnect()

        guard let socketURL = configuration.webSocketURL() else {
            onDisconnect("Invalid websocket URL")
            return
        }

        self.onSnapshot = onSnapshot
        self.onDisconnect = onDisconnect
        isActive = true

        let task = session.webSocketTask(with: socketURL)
        webSocketTask = task
        task.resume()
        receiveNextMessage()
    }

    func disconnect() {
        isActive = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        onSnapshot = nil
        onDisconnect = nil
    }

    private func receiveNextMessage() {
        guard isActive, let webSocketTask else {
            return
        }

        webSocketTask.receive { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case let .success(message):
                self.handle(message)
                self.receiveNextMessage()
            case let .failure(error):
                if self.isActive {
                    self.onDisconnect?(error.localizedDescription)
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case let .string(payload):
            data = payload.data(using: .utf8)
        case let .data(payload):
            data = payload
        @unknown default:
            data = nil
        }

        guard let data else {
            return
        }

        do {
            let event = try JSONDecoder().decode(ThreadsSnapshotEvent.self, from: data)
            guard event.type == "threads_snapshot" else {
                return
            }
            onSnapshot?(event.data)
        } catch {
            onDisconnect?("Malformed websocket payload")
        }
    }
}
