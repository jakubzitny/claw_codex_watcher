import SwiftUI

struct ThreadsView: View {
    @ObservedObject var store: WatcherStore

    private var selectedBinding: Binding<String?> {
        Binding(
            get: { store.selectedThreadID },
            set: { newValue in
                Task { @MainActor in
                    await store.selectThread(id: newValue)
                }
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(store.threads, selection: selectedBinding) { thread in
                ThreadRowView(thread: thread)
                    .tag(Optional(thread.id))
            }
            .accessibilityIdentifier("threads.list")
            .overlay {
                if store.threads.isEmpty {
                    ContentUnavailableView(
                        "No Threads",
                        systemImage: "tray",
                        description: Text("Connect to your watcher backend and pull active threads.")
                    )
                }
            }
            .refreshable {
                await store.refreshThreads()
            }
            .navigationTitle("Watcher")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { @MainActor in
                            await store.refreshThreads()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh threads")
                }
            }
        } detail: {
            ThreadDetailView(store: store)
        }
        .task {
            await store.startIfNeeded()
        }
    }
}

private struct ThreadRowView: View {
    let thread: ThreadSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(thread.status.color)
                    .frame(width: 9, height: 9)
                Text(thread.shortTitle)
                    .font(.headline)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Text(relativeAge(from: thread.updatedAt))
                if thread.planTotalSteps > 0 {
                    Text("plan \(thread.planCompletedSteps)/\(thread.planTotalSteps)")
                }
                if thread.runningCommandCount > 0 {
                    Text("cmd \(thread.runningCommandCount)")
                }
                if thread.approvalPendingCount > 0 {
                    Text("approval")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private func relativeAge(from isoDate: String) -> String {
    guard let date = parseISODate(isoDate) else {
        return "unknown"
    }

    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}
