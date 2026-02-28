import SwiftUI

struct ThreadDetailView: View {
    @ObservedObject var store: WatcherStore

    var body: some View {
        Group {
            if let detail = store.selectedThreadDetail {
                List {
                    headerSection(for: detail)

                    if let plan = detail.plan {
                        Section("Plan") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("\(plan.completed)/\(plan.total) complete")
                                    Spacer()
                                    Text("\(plan.completionPercent)%")
                                        .foregroundStyle(.secondary)
                                }
                                ProgressView(value: Double(plan.completed), total: Double(max(plan.total, 1)))
                                ForEach(Array(plan.steps.enumerated()), id: \.offset) { _, step in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text(step.status)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                            .frame(minWidth: 88, alignment: .leading)
                                        Text(step.step)
                                            .font(.callout)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    if !detail.artifacts.isEmpty {
                        Section("Artifacts") {
                            ForEach(detail.artifacts) { artifact in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(artifact.path)
                                        .font(.callout.monospaced())
                                        .lineLimit(2)
                                    Text(artifact.exists ? "exists" : "missing")
                                        .font(.caption)
                                        .foregroundStyle(artifact.exists ? .green : .secondary)
                                }
                            }
                        }
                    }

                    Section("Timeline") {
                        ForEach(detail.timeline) { entry in
                            TimelineRow(entry: entry)
                        }
                    }
                }
                .animation(.default, value: detail.summary.updatedAt)
                .navigationTitle(detail.summary.shortTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { @MainActor in
                                await store.refreshSelectedThreadDetailIfNeeded(force: true)
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise.circle")
                        }
                        .accessibilityLabel("Refresh thread detail")
                    }
                }
            } else if store.threads.isEmpty {
                ContentUnavailableView(
                    "No Thread Selected",
                    systemImage: "rectangle.and.text.magnifyingglass",
                    description: Text("Pick a thread from the list once data is available.")
                )
            } else if store.isLoadingDetail {
                ProgressView("Loading thread detail...")
            } else {
                ContentUnavailableView(
                    "Thread Detail",
                    systemImage: "text.bubble",
                    description: Text("Select a thread to inspect messages, tools, and plan progress.")
                )
            }
        }
        .overlay(alignment: .bottom) {
            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func headerSection(for detail: ThreadDetail) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    StatusPill(status: detail.summary.status)
                    Spacer()
                    Text(connectionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(detail.summary.cwd)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                HStack(spacing: 10) {
                    Label("\(detail.summary.messageCount)", systemImage: "text.bubble")
                    Label("\(detail.summary.toolCallCount)", systemImage: "wrench.and.screwdriver")
                    Label("\(detail.summary.errorCount)", systemImage: "exclamationmark.triangle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var connectionText: String {
        switch store.connectionState {
        case .idle:
            return "idle"
        case .connecting:
            return "connecting"
        case .live:
            return "live"
        case .polling:
            return "polling"
        }
    }
}

private struct TimelineRow: View {
    let entry: TimelineEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch entry.payload {
            case let .message(message):
                HStack {
                    Label(message.role.rawValue, systemImage: roleSymbol(for: message.role))
                        .font(.headline)
                    Spacer()
                    Text(formattedTime(from: message.timestamp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let phase = message.phase, !phase.isEmpty {
                    Text(phase)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(message.text)
                    .font(.callout)
                    .textSelection(.enabled)

            case let .toolCall(call):
                HStack {
                    Label(call.name, systemImage: "terminal")
                        .font(.headline)
                    Spacer()
                    Text(formattedTime(from: call.timestamp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(commandStateText(for: call))
                    .font(.caption.monospaced())
                    .foregroundStyle(call.errored ? .red : .secondary)

                if !call.argumentsPreview.isEmpty {
                    Text(call.argumentsPreview)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let outputPreview = call.outputPreview, !outputPreview.isEmpty {
                    Text(outputPreview)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func roleSymbol(for role: MessageRole) -> String {
        switch role {
        case .user:
            return "person"
        case .assistant:
            return "brain"
        case .developer:
            return "hammer"
        }
    }

    private func commandStateText(for call: ToolCall) -> String {
        if call.pending, call.needsApproval {
            return "needs approval"
        }
        if call.pending {
            return "running"
        }
        if call.errored {
            return "failed"
        }
        return "done"
    }
}

private func formattedTime(from isoDate: String) -> String {
    guard let date = parseISODate(isoDate) else {
        return "unknown"
    }

    let formatter = DateFormatter()
    formatter.timeStyle = .medium
    formatter.dateStyle = .none
    return formatter.string(from: date)
}
