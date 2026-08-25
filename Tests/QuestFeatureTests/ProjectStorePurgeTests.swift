import Testing
import Foundation
@testable import QuestFeature

@MainActor
@Suite("ProjectStore — purge and empty trash")
struct ProjectStorePurgeTests {
    private func makeStore() -> ProjectStore { makeProjectStore(InMemoryProjectRepository()) }

    private func projectWithEpic(_ store: ProjectStore) throws -> (project: Project, epic: WorkItem) {
        let project = store.createProject(name: "Quest", kind: .software, actor: .user)
        let epic = try store.createItem(projectID: project.id, parentID: nil, type: .epic,
                                        title: "Shell", statusID: "todo", actor: .user)
        return (project, epic)
    }

    @Test("purging a trashed item removes it from the document")
    func purgeRemoves() throws {
        let store = makeStore()
        let (project, epic) = try projectWithEpic(store)
        try store.deleteItem(epic.id, actor: .user)

        try store.purgeItem(epic.id, actor: .user)

        #expect(!store.allItems(in: project.id).contains { $0.id == epic.id })
    }

    /// The guard that makes purge safe to expose over MCP: a live item is never
    /// destroyed, however the id arrived.
    @Test("purging an item that is not in the trash throws and changes nothing")
    func refusesLiveItem() throws {
        let store = makeStore()
        let (project, epic) = try projectWithEpic(store)

        #expect(throws: QuestError.itemNotInTrash(epic.id)) {
            try store.purgeItem(epic.id, actor: .user)
        }
        #expect(store.allItems(in: project.id).count == 1)
    }

    /// Leaving a descendant behind gives it a parentID pointing at nothing, and
    /// every surface renders epic → descendants — so the survivor would be
    /// live, invisible and unreachable.
    @Test("purging an epic takes its descendants with it")
    func cascades() throws {
        let store = makeStore()
        let (project, epic) = try projectWithEpic(store)
        let child = try store.createItem(projectID: project.id, parentID: epic.id, type: .task,
                                         title: "Header", statusID: "todo", actor: .user)
        try store.deleteItem(epic.id, actor: .user)

        try store.purgeItem(epic.id, actor: .user)

        #expect(store.allItems(in: project.id).isEmpty)
        #expect(!store.allItems(in: project.id).contains { $0.id == child.id })
    }

    /// The activity feed outlives the item, so it has to carry the title —
    /// `itemID` now resolves to nothing.
    @Test("the purge is logged with the title, which no longer resolves")
    func logsTitle() throws {
        let store = makeStore()
        let (project, epic) = try projectWithEpic(store)
        try store.deleteItem(epic.id, actor: .user)

        try store.purgeItem(epic.id, actor: .user)

        let last = store.activity(for: project.id).last
        #expect(last?.summary.contains("Shell") == true)
    }

    @Test("empty trash removes trashed items and leaves live ones alone")
    func emptyTrashSpares() throws {
        let store = makeStore()
        let (project, epic) = try projectWithEpic(store)
        let keep = try store.createItem(projectID: project.id, parentID: nil, type: .epic,
                                        title: "Keep", statusID: "todo", actor: .user)
        try store.deleteItem(epic.id, actor: .user)

        let outcome = store.emptyTrash(actor: .user)

        #expect(outcome.purgedItems == 1)
        #expect(outcome.failures.isEmpty)
        #expect(store.allItems(in: project.id).map(\.id) == [keep.id])
    }

    @Test("empty trash removes trashed projects too")
    func emptyTrashPurgesProjects() throws {
        let store = makeStore()
        let project = store.createProject(name: "Doomed", kind: .general, actor: .user)
        try store.deleteProject(project.id, actor: .user)

        let outcome = store.emptyTrash(actor: .user)

        #expect(outcome.purgedProjects == 1)
        #expect(store.trashedProjects.isEmpty)
        #expect(store.projects.isEmpty)
    }

    /// An epic and its child are BOTH listed in the trash, so the plan contains
    /// both ids — and purging the epic already took the child. That must read
    /// as success, not as a failure the user is told about.
    @Test("a cascade that pre-empts a later purge is not reported as a failure")
    func cascadeIsNotAFailure() throws {
        let store = makeStore()
        let (project, epic) = try projectWithEpic(store)
        _ = try store.createItem(projectID: project.id, parentID: epic.id, type: .task,
                                 title: "Header", statusID: "todo", actor: .user)
        try store.deleteItem(epic.id, actor: .user)   // cascades onto the child

        let outcome = store.emptyTrash(actor: .user)

        #expect(outcome.failures.isEmpty)
        #expect(store.allItems(in: project.id).isEmpty)
    }

    @Test("setRole stamps an existing item without logging it as a user edit")
    func setRole() throws {
        let store = makeStore()
        let (project, epic) = try projectWithEpic(store)
        let before = store.activity(for: project.id).count

        try store.setRole(.inbox, on: epic.id)

        #expect(store.allItems(in: project.id).first?.role == .inbox)
        // Adoption is bookkeeping, not something the user did.
        #expect(store.activity(for: project.id).count == before)
    }

    @Test("setRole on an unknown item throws")
    func setRoleUnknown() {
        let store = makeStore()
        #expect(throws: QuestError.self) { try store.setRole(.inbox, on: UUID()) }
    }

    @Test("emptying an already-empty trash destroys nothing and reports nothing")
    func emptyTrashOnEmpty() throws {
        let store = makeStore()
        _ = try projectWithEpic(store)

        let outcome = store.emptyTrash(actor: .user)

        #expect(outcome == TrashPurgeOutcome(purgedItems: 0, purgedProjects: 0, failures: []))
    }
}
