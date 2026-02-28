import CarPlay
import Combine
import Foundation
import UIKit

@MainActor
final class CarPlayCoordinator {
    private let interfaceController: CPInterfaceController
    private let store: WatcherStore

    private var rootTemplate: CPListTemplate?
    private var cancellables = Set<AnyCancellable>()

    init(interfaceController: CPInterfaceController, store: WatcherStore) {
        self.interfaceController = interfaceController
        self.store = store
    }

    func start() {
        bindStore()

        Task {
            await store.startIfNeeded()
            renderRootTemplate(threads: store.threads)
        }
    }

    func stop() {
        cancellables.removeAll()
    }

    private func bindStore() {
        store.$threads
            .receive(on: RunLoop.main)
            .sink { [weak self] threads in
                self?.renderRootTemplate(threads: threads)
            }
            .store(in: &cancellables)
    }

    private func renderRootTemplate(threads: [ThreadSummary]) {
        let section = CPListSection(
            items: listItems(for: threads),
            header: sectionHeader,
            sectionIndexTitle: nil
        )

        if let rootTemplate {
            rootTemplate.updateSections([section])
            return
        }

        let template = CPListTemplate(title: "Codex Watcher", sections: [section])
        template.emptyViewTitleVariants = ["No Active Threads"]
        template.emptyViewSubtitleVariants = ["Connect to your local watcher API to see sessions."]

        rootTemplate = template
        interfaceController.setRootTemplate(template, animated: true, completion: nil)
    }

    private var sectionHeader: String {
        switch store.connectionState {
        case .live:
            return "Live"
        case .connecting:
            return "Connecting"
        case .polling:
            return "Polling"
        case .idle:
            return "Idle"
        }
    }

    private func listItems(for threads: [ThreadSummary]) -> [CPListItem] {
        let limitedThreads = Array(threads.prefix(12))
        guard !limitedThreads.isEmpty else {
            return [
                CPListItem(
                    text: "No threads yet",
                    detailText: "Start Codex and keep the watcher API running on your machine."
                )
            ]
        }

        return limitedThreads.map { thread in
            let detail = "\(thread.status.rawValue) | msg \(thread.messageCount) | cmd \(thread.runningCommandCount)"
            let item = CPListItem(text: thread.shortTitle, detailText: detail)

            item.handler = { [weak self] _, completion in
                Task { @MainActor [weak self] in
                    await self?.showThreadDetail(threadID: thread.id)
                    completion()
                }
            }

            return item
        }
    }

    private func showThreadDetail(threadID: String) async {
        guard let detail = await store.loadThreadDetail(threadID: threadID, force: true) else {
            let item = CPListItem(
                text: "Unable to Load Thread",
                detailText: store.errorMessage ?? "Unknown issue"
            )
            let errorTemplate = CPListTemplate(
                title: "Watcher Error",
                sections: [CPListSection(items: [item])]
            )
            interfaceController.pushTemplate(errorTemplate, animated: true, completion: nil)
            return
        }

        let detailTemplate = makeDetailTemplate(for: detail)
        interfaceController.pushTemplate(detailTemplate, animated: true, completion: nil)
    }

    private func makeDetailTemplate(for detail: ThreadDetail) -> CPListTemplate {
        var sections: [CPListSection] = []

        let summaryItem = CPListItem(
            text: detail.summary.shortTitle,
            detailText: "\(detail.summary.status.rawValue.capitalized) | \(detail.summary.cwd)"
        )
        sections.append(CPListSection(items: [summaryItem], header: "Summary", sectionIndexTitle: nil))

        if let plan = detail.plan {
            let planSummary = CPListItem(
                text: "Plan Progress",
                detailText: "\(plan.completed)/\(plan.total) (\(plan.completionPercent)%)"
            )
            let planSteps = plan.steps.prefix(6).map { step in
                CPListItem(text: step.step, detailText: step.status)
            }
            sections.append(
                CPListSection(items: [planSummary] + planSteps, header: "Plan", sectionIndexTitle: nil)
            )
        }

        let recentMessages = detail.messages.suffix(8).map { message in
            CPListItem(
                text: "\(message.role.rawValue): \(message.text.compactPreview(maxLength: 64))",
                detailText: formattedRelativeTime(from: message.timestamp)
            )
        }
        if !recentMessages.isEmpty {
            sections.append(
                CPListSection(items: recentMessages, header: "Recent Messages", sectionIndexTitle: nil)
            )
        }

        let recentTools = detail.toolCalls.suffix(6).map { call in
            CPListItem(
                text: call.name,
                detailText: call.pending ? "running" : (call.errored ? "failed" : "done")
            )
        }
        if !recentTools.isEmpty {
            sections.append(
                CPListSection(items: recentTools, header: "Tool Calls", sectionIndexTitle: nil)
            )
        }

        return CPListTemplate(title: "Thread", sections: sections)
    }

    private func formattedRelativeTime(from rawTimestamp: String) -> String {
        guard let date = parseISODate(rawTimestamp) else {
            return "unknown"
        }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

private extension String {
    func compactPreview(maxLength: Int) -> String {
        let trimmed = replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count > maxLength else {
            return trimmed
        }

        let index = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        return String(trimmed[..<index]) + "..."
    }
}
