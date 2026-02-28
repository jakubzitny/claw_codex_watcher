import XCTest
@testable import WatcherIOS

@MainActor
final class WatcherAPIClientTests: XCTestCase {
    func testFetchThreadsIncludesAuthHeadersAndDecodesPayload() async throws {
        let session = MockSession()
        session.nextData = """
        [
          {
            "id": "thread-1",
            "title": "Inspect failing CI",
            "shortTitle": "Inspect failing CI",
            "cwd": "/repo",
            "source": "codex",
            "modelProvider": "openai",
            "createdAt": "2026-02-28T12:00:00.000000+00:00",
            "updatedAt": "2026-02-28T12:10:00.000000+00:00",
            "archived": false,
            "status": "running",
            "messageCount": 2,
            "toolCallCount": 1,
            "errorCount": 0,
            "artifactCount": 0,
            "runningCommandCount": 1,
            "approvalPendingCount": 0,
            "planTotalSteps": 3,
            "planCompletedSteps": 1
          }
        ]
        """.data(using: .utf8)!

        let client = WatcherAPIClient(session: session)
        let configuration = WatcherConfiguration(
            serverURL: URL(string: "http://127.0.0.1:18000")!,
            authToken: "abc123"
        )

        let threads = try await client.fetchThreads(configuration: configuration, limit: 50)

        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].id, "thread-1")
        XCTAssertEqual(session.lastRequest?.url?.absoluteString, "http://127.0.0.1:18000/api/v1/threads?limit=50")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "X-Watcher-Token"), "abc123")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer abc123")
    }

    func testFetchThreadDetailThrowsOnErrorStatus() async {
        let session = MockSession()
        session.responseStatusCode = 401
        session.nextData = Data("{}".utf8)

        let client = WatcherAPIClient(session: session)
        let configuration = WatcherConfiguration.default

        do {
            _ = try await client.fetchThreadDetail(threadID: "missing", configuration: configuration)
            XCTFail("Expected request failure")
        } catch let error as WatcherAPIError {
            if case let .requestFailed(statusCode) = error {
                XCTAssertEqual(statusCode, 401)
            } else {
                XCTFail("Unexpected error case")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

@MainActor
private final class MockSession: URLSessioning {
    var nextData = Data()
    var responseStatusCode = 200
    var lastRequest: URLRequest?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: responseStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (nextData, response)
    }
}
