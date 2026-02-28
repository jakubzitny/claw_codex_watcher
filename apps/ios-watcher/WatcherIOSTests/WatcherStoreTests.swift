import XCTest
@testable import WatcherIOS

@MainActor
final class WatcherStoreTests: XCTestCase {
    func testStartLoadsThreadsAndSelectsFirstThread() async {
        let service = MockWatcherService()
        service.threads = [
            makeThreadSummary(id: "thread-1", updatedAt: "2026-02-28T12:00:00.000000+00:00"),
            makeThreadSummary(id: "thread-2", updatedAt: "2026-02-28T11:00:00.000000+00:00")
        ]
        service.detailsByID["thread-1"] = makeThreadDetail(id: "thread-1")

        let store = WatcherStore(
            configurationStore: MockConfigurationStore(),
            service: service,
            stream: MockThreadsStream(),
            pollingIntervalNanoseconds: 3_000_000_000
        )

        await store.startIfNeeded()

        XCTAssertEqual(store.threads.count, 2)
        XCTAssertEqual(store.selectedThreadID, "thread-1")
        XCTAssertEqual(store.selectedThreadDetail?.summary.id, "thread-1")
    }

    func testSelectThreadLoadsDetailFromService() async {
        let service = MockWatcherService()
        service.threads = [makeThreadSummary(id: "thread-1", updatedAt: "2026-02-28T12:00:00.000000+00:00")]
        service.detailsByID["thread-1"] = makeThreadDetail(id: "thread-1")

        let store = WatcherStore(
            configurationStore: MockConfigurationStore(),
            service: service,
            stream: MockThreadsStream(),
            pollingIntervalNanoseconds: 3_000_000_000
        )

        await store.refreshThreads()
        await store.selectThread(id: "thread-1")

        XCTAssertEqual(store.selectedThreadDetail?.summary.id, "thread-1")
        XCTAssertEqual(service.detailCallIDs, ["thread-1"])
    }

    func testSaveConfigurationValidatesURL() async {
        let store = WatcherStore(
            configurationStore: MockConfigurationStore(),
            service: MockWatcherService(),
            stream: MockThreadsStream(),
            pollingIntervalNanoseconds: 3_000_000_000
        )

        do {
            try await store.saveConfiguration(serverURLRaw: "ftp://example.com", authToken: nil)
            XCTFail("Expected invalid URL error")
        } catch let error as WatcherStore.ConfigurationError {
            XCTAssertEqual(error, .invalidServerURL)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeThreadSummary(id: String, updatedAt: String) -> ThreadSummary {
        ThreadSummary(
            id: id,
            title: id,
            shortTitle: id,
            cwd: "/repo",
            source: "codex",
            modelProvider: "openai",
            createdAt: "2026-02-28T10:00:00.000000+00:00",
            updatedAt: updatedAt,
            archived: false,
            status: .running,
            messageCount: 1,
            toolCallCount: 1,
            errorCount: 0,
            artifactCount: 0,
            runningCommandCount: 1,
            approvalPendingCount: 0,
            planTotalSteps: 0,
            planCompletedSteps: 0
        )
    }

    private func makeThreadDetail(id: String) -> ThreadDetail {
        ThreadDetail(
            summary: makeThreadSummary(id: id, updatedAt: "2026-02-28T12:00:00.000000+00:00"),
            messages: [
                ThreadMessage(
                    id: "msg-1",
                    timestamp: "2026-02-28T12:00:00.000000+00:00",
                    role: .assistant,
                    phase: "final_answer",
                    text: "done"
                )
            ],
            toolCalls: [],
            artifacts: [],
            plan: nil
        )
    }
}

private final class MockConfigurationStore: WatcherConfigurationStoring {
    var configuration = WatcherConfiguration.default

    func load() -> WatcherConfiguration { configuration }

    func save(_ configuration: WatcherConfiguration) {
        self.configuration = configuration
    }

    func normalizeServerURL(from rawValue: String) -> URL? {
        WatcherConfigurationStore().normalizeServerURL(from: rawValue)
    }
}

@MainActor
private final class MockWatcherService: WatcherServing {
    var threads: [ThreadSummary] = []
    var detailsByID: [String: ThreadDetail] = [:]
    var detailCallIDs: [String] = []

    func fetchThreads(configuration: WatcherConfiguration, limit: Int) async throws -> [ThreadSummary] {
        threads
    }

    func fetchThreadDetail(threadID: String, configuration: WatcherConfiguration) async throws -> ThreadDetail {
        detailCallIDs.append(threadID)
        guard let detail = detailsByID[threadID] else {
            throw WatcherAPIError.requestFailed(statusCode: 404)
        }
        return detail
    }

    func fetchThreadEvents(
        threadID: String,
        configuration: WatcherConfiguration,
        limit: Int
    ) async throws -> [ThreadEvent] {
        []
    }
}

private final class MockThreadsStream: ThreadsStreaming {
    func connect(
        configuration: WatcherConfiguration,
        onSnapshot: @escaping @Sendable ([ThreadSummary]) -> Void,
        onDisconnect: @escaping @Sendable (String) -> Void
    ) {}

    func disconnect() {}
}
