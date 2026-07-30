import Testing
import Foundation
@testable import QuestFeature

@Suite("InboxEpic")
struct InboxEpicTests {
    private let projectID = UUID()

    private func epic(_ title: String, deleted: Bool = false) -> WorkItem {
        WorkItem(id: UUID(), projectID: projectID, parentID: nil, type: .epic,
                 title: title, statusID: "todo",
                 deletedAt: deleted ? Date() : nil)
    }

    private func task(_ title: String, parent: UUID?) -> WorkItem {
        WorkItem(id: UUID(), projectID: projectID, parentID: parent, type: .task,
                 title: title, statusID: "todo")
    }

    @Test("with no items at all, the caller must create the Inbox")
    func noEpics() {
        #expect(InboxEpic.resolve(in: []) == .create)
    }

    @Test("a project with tasks but no epic still creates one")
    func tasksOnly() {
        #expect(InboxEpic.resolve(in: [task("stray", parent: nil)]) == .create)
    }

    @Test("an existing live Inbox is reused")
    func existingInbox() {
        let inbox = epic(InboxEpic.title)
        #expect(InboxEpic.resolve(in: [epic("Platform"), inbox]) == .existing(inbox.id))
    }

    @Test("a soft-deleted Inbox is ignored, not reused")
    func deletedInbox() {
        #expect(InboxEpic.resolve(in: [epic(InboxEpic.title, deleted: true)]) == .create)
    }

    @Test("a live Inbox wins over a soft-deleted one of the same name")
    func deletedAndLiveInbox() {
        let live = epic(InboxEpic.title)
        let dead = epic(InboxEpic.title, deleted: true)
        #expect(InboxEpic.resolve(in: [dead, live]) == .existing(live.id))
    }

    /// A capture must never land under a trashed epic and vanish from the list.
    @Test("a project whose only epic is soft-deleted creates a new Inbox")
    func onlyEpicDeleted() {
        #expect(InboxEpic.resolve(in: [epic("Platform", deleted: true)]) == .create)
    }

    @Test("an unrelated live epic is never borrowed as the capture target")
    func neverAnArbitraryEpic() {
        #expect(InboxEpic.resolve(in: [epic("Platform"), epic("Design")]) == .create)
    }
}

@Suite("StatusScheme.openingStatusID")
struct OpeningStatusTests {
    @Test("the first not-done status opens a new item")
    func firstNotDone() {
        #expect(StatusScheme.softwareDefault.openingStatusID == "backlog")
    }

    @Test("a scheme without 'todo' still resolves — the editor can remove it")
    func todoRemoved() {
        let scheme = StatusScheme(statuses: StatusScheme.softwareDefault.statuses
            .filter { $0.id != "todo" && $0.id != "backlog" })
        #expect(scheme.openingStatusID == "in_progress")
    }

    @Test("an all-done scheme falls back to the first status")
    func allDone() {
        let scheme = StatusScheme(statuses: [
            Status(id: "shipped", name: "Shipped", category: .done, colorToken: "success"),
        ])
        #expect(scheme.openingStatusID == "shipped")
    }

    @Test("an empty scheme has none, so the caller withholds the action")
    func empty() {
        #expect(StatusScheme(statuses: []).openingStatusID == nil)
    }
}
