import Foundation

@MainActor
final class WatcherStore: ObservableObject {
    enum ConnectionState: String {
        case idle
        case connecting
        case live
        case polling
    }

    enum ConfigurationError: LocalizedError, Equatable {
        case invalidServerURL

        var errorDescription: String? {
            switch self {
            case .invalidServerURL:
                return "Server URL must be a valid http:// or https:// address."
            }
        }
    }

    @Published private(set) var configuration: WatcherConfiguration
    @Published private(set) var threads: [ThreadSummary] = []
    @Published var selectedThreadID: String?
    @Published private(set) var selectedThreadDetail: ThreadDetail?
    @Published private(set) var connectionState: ConnectionState = .idle
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoadingThreads = false
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var lastRefreshAt: Date?

    private let configurationStore: WatcherConfigurationStoring
    private let service: WatcherServing
    private let stream: ThreadsStreaming
    private let pollingIntervalNanoseconds: UInt64

    private var detailCache: [String: ThreadDetail] = [:]
    private var hasStarted = false
    private var pollingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0

    init(
        configurationStore: WatcherConfigurationStoring,
        service: WatcherServing,
        stream: ThreadsStreaming,
        pollingIntervalNanoseconds: UInt64 = 20_000_000_000
    ) {
        self.configurationStore = configurationStore
        self.service = service
        self.stream = stream
        self.pollingIntervalNanoseconds = pollingIntervalNanoseconds
        configuration = configurationStore.load()
    }

    func startIfNeeded() async {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        connectionState = .connecting

        await refreshThreads()
        connectWebSocket()
        startPollingLoop()
    }

    func stop() {
        hasStarted = false
        pollingTask?.cancel()
        pollingTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        stream.disconnect()
        connectionState = .idle
    }

    func refreshThreads() async {
        if !isLoadingThreads {
            isLoadingThreads = true
        }
        defer { isLoadingThreads = false }

        do {
            let payload = try await service.fetchThreads(configuration: configuration, limit: 100)
            applyThreads(payload)
            errorMessage = nil
            lastRefreshAt = Date()
            if connectionState == .idle || connectionState == .connecting {
                connectionState = .polling
            }
            await refreshSelectedThreadDetailIfNeeded(force: false)
        } catch {
            errorMessage = error.localizedDescription
            if connectionState == .idle || connectionState == .connecting {
                connectionState = .polling
            }
        }
    }

    func refreshSelectedThreadDetailIfNeeded(force: Bool) async {
        guard let selectedThreadID else {
            selectedThreadDetail = nil
            return
        }

        _ = await loadThreadDetail(threadID: selectedThreadID, force: force)
    }

    @discardableResult
    func loadThreadDetail(threadID: String, force: Bool = false) async -> ThreadDetail? {
        if !force,
           let cached = detailCache[threadID],
           let latestSummary = threads.first(where: { $0.id == threadID }),
           cached.summary.updatedAt == latestSummary.updatedAt {
            if selectedThreadID == threadID {
                selectedThreadDetail = cached
            }
            return cached
        }

        isLoadingDetail = true
        defer { isLoadingDetail = false }

        do {
            let detail = try await service.fetchThreadDetail(threadID: threadID, configuration: configuration)
            detailCache[threadID] = detail
            if selectedThreadID == threadID {
                selectedThreadDetail = detail
            }
            errorMessage = nil
            return detail
        } catch {
            if selectedThreadID == threadID {
                errorMessage = error.localizedDescription
            }
            return nil
        }
    }

    func selectThread(id: String?) async {
        selectedThreadID = id

        guard let id else {
            selectedThreadDetail = nil
            return
        }

        if let cached = detailCache[id] {
            selectedThreadDetail = cached
        } else {
            selectedThreadDetail = nil
        }

        _ = await loadThreadDetail(threadID: id, force: false)
    }

    func saveConfiguration(serverURLRaw: String, authToken: String?) async throws {
        guard let normalizedURL = configurationStore.normalizeServerURL(from: serverURLRaw) else {
            throw ConfigurationError.invalidServerURL
        }

        configuration = WatcherConfiguration(serverURL: normalizedURL, authToken: authToken).normalized()
        configurationStore.save(configuration)

        detailCache.removeAll()
        selectedThreadDetail = nil

        reconnectTask?.cancel()
        stream.disconnect()
        connectionState = .connecting
        reconnectAttempt = 0

        await refreshThreads()
        connectWebSocket()
    }

    private func applyThreads(_ incomingThreads: [ThreadSummary]) {
        threads = incomingThreads.sorted { left, right in
            guard let leftDate = left.updatedDate, let rightDate = right.updatedDate else {
                return left.updatedAt > right.updatedAt
            }
            return leftDate > rightDate
        }

        guard !threads.isEmpty else {
            selectedThreadID = nil
            selectedThreadDetail = nil
            return
        }

        guard let selectedThreadID else {
            self.selectedThreadID = threads.first?.id
            return
        }

        if !threads.contains(where: { $0.id == selectedThreadID }) {
            self.selectedThreadID = threads.first?.id
            selectedThreadDetail = nil
        }
    }

    private func connectWebSocket() {
        stream.connect(
            configuration: configuration,
            onSnapshot: { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    self.reconnectAttempt = 0
                    self.connectionState = .live
                    self.errorMessage = nil
                    self.applyThreads(snapshot)
                    self.lastRefreshAt = Date()
                    await self.refreshSelectedThreadDetailIfNeeded(force: false)
                }
            },
            onDisconnect: { [weak self] message in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    guard self.hasStarted else {
                        return
                    }
                    self.connectionState = .polling
                    self.errorMessage = "Live updates disconnected: \(message). Using polling."
                    self.scheduleReconnect()
                }
            }
        )
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectAttempt += 1
        let seconds = min(pow(2.0, Double(reconnectAttempt)), 30.0)
        let nanoseconds = UInt64(seconds * 1_000_000_000)

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            await MainActor.run {
                guard let self else {
                    return
                }
                guard self.hasStarted else {
                    return
                }
                self.connectWebSocket()
            }
        }
    }

    private func startPollingLoop() {
        pollingTask?.cancel()

        pollingTask = Task { [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: pollingIntervalNanoseconds)
                guard !Task.isCancelled else {
                    return
                }
                await self.refreshThreads()
            }
        }
    }
}
