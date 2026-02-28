import Foundation

enum ThreadStatus: String, Codable, CaseIterable {
    case running
    case thinking
    case completed
    case waiting
    case failed
}

enum MessageRole: String, Codable {
    case user
    case assistant
    case developer
}

struct ThreadSummary: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let shortTitle: String
    let cwd: String
    let source: String
    let modelProvider: String
    let createdAt: String
    let updatedAt: String
    let archived: Bool
    let status: ThreadStatus
    let messageCount: Int
    let toolCallCount: Int
    let errorCount: Int
    let artifactCount: Int
    let runningCommandCount: Int
    let approvalPendingCount: Int
    let planTotalSteps: Int
    let planCompletedSteps: Int

    var updatedDate: Date? {
        parseISODate(updatedAt)
    }

    var createdDate: Date? {
        parseISODate(createdAt)
    }
}

struct ThreadMessage: Codable, Identifiable, Equatable {
    let id: String
    let timestamp: String
    let role: MessageRole
    let phase: String?
    let text: String
}

struct ToolCall: Codable, Identifiable, Equatable {
    let id: String
    let timestamp: String
    let name: String
    let argumentsPreview: String
    let outputPreview: String?
    let exitCode: Int?
    let errored: Bool
    let pending: Bool
    let needsApproval: Bool
}

struct Artifact: Codable, Identifiable, Equatable {
    let id: String
    let timestamp: String
    let path: String
    let exists: Bool
}

struct PlanStep: Codable, Equatable {
    let step: String
    let status: String
}

struct PlanProgress: Codable, Equatable {
    let updatedAt: String
    let total: Int
    let completed: Int
    let inProgress: Int
    let pending: Int
    let steps: [PlanStep]

    var completionPercent: Int {
        guard total > 0 else { return 0 }
        return Int((Double(completed) / Double(total) * 100.0).rounded())
    }
}

struct ThreadDetail: Codable, Equatable {
    let summary: ThreadSummary
    let messages: [ThreadMessage]
    let toolCalls: [ToolCall]
    let artifacts: [Artifact]
    let plan: PlanProgress?

    var timeline: [TimelineEntry] {
        var entries = messages.map { message in
            TimelineEntry(
                id: "message-\(message.id)",
                timestamp: message.timestamp,
                payload: .message(message)
            )
        }
        entries.append(contentsOf: toolCalls.map { call in
            TimelineEntry(
                id: "tool-\(call.id)",
                timestamp: call.timestamp,
                payload: .toolCall(call)
            )
        })
        return entries.sorted { $0.timestamp > $1.timestamp }
    }
}

struct ThreadEvent: Codable, Identifiable, Equatable {
    var id: String { "\(timestamp)-\(type)-\(subtype ?? "")" }

    let timestamp: String
    let type: String
    let subtype: String?
    let summary: String
}

struct ThreadsSnapshotEvent: Codable, Equatable {
    let type: String
    let at: String
    let data: [ThreadSummary]
}

struct TimelineEntry: Identifiable, Equatable {
    enum Payload: Equatable {
        case message(ThreadMessage)
        case toolCall(ToolCall)
    }

    let id: String
    let timestamp: String
    let payload: Payload
}
