import Testing
import Foundation
@testable import QuestFeature

@MainActor
@Suite("ProjectStore — scheme")
struct ProjectStoreSchemeTests {
    private func makeStore() -> (ProjectStore, Project) {
        let store = ProjectStore(repository: InMemoryProjectRepository())
        return (store, store.createProject(name: "Quest", kind: .software, actor: .user))
    }

    private func planRemovingReview(_ store: ProjectStore, _ project: Project)
        -> SchemePlan.Plan? {
        var proposed = StatusScheme.softwareDefault
        proposed.statuses.removeAll { $0.id == "in_review" }
        return SchemePlan.plan(current: .softwareDefault, proposed: proposed,
                               reassignments: ["in_review": "todo"],
                               items: store.allItems(in: project.id)).value
    }

    @Test("applying a plan rewrites the scheme and reassigns items")
    func apply() throws {
        let (store, project) = makeStore()
        let epic = try store.createItem(projectID: project.id, parentID: nil, type: .epic,
                                        title: "E", statusID: "todo", actor: .user)
        let item = try store.createItem(projectID: project.id, parentID: epic.id, type: .task,
                                        title: "T", statusID: "in_review", actor: .user)
        let plan = try #require(planRemovingReview(store, project))

        try store.applyScheme(plan, to: project.id, actor: .user)

        let scheme = try #require(store.openProject(project.id)?.project.statusScheme)
        #expect(scheme.status(id: "in_review") == nil)
        #expect(store.items(in: project.id).first { $0.id == item.id }?.statusID == "todo")
    }

    @Test("exactly one activity event is appended, of kind schemeUpdated")
    func logsOnce() throws {
        let (store, project) = makeStore()
        let before = store.activity(for: project.id).count
        let plan = try #require(planRemovingReview(store, project))

        try store.applyScheme(plan, to: project.id, actor: .agent)

        let events = store.activity(for: project.id)
        #expect(events.count == before + 1)
        #expect(events.last?.kind == .schemeUpdated)
        #expect(events.last?.actor == .agent)
    }

    @Test("moving a status into done stamps closedAt; moving out clears it")
    func categoryRestamp() throws {
        let (store, project) = makeStore()
        let epic = try store.createItem(projectID: project.id, parentID: nil, type: .epic,
                                        title: "E", statusID: "in_review", actor: .user)

        var toDone = StatusScheme.softwareDefault
        toDone.statuses[3] = Status(id: "in_review", name: "In Review",
                                    category: .done, colorToken: "success")
        let closing = try #require(SchemePlan.plan(
            current: .softwareDefault, proposed: toDone, reassignments: [:],
            items: store.allItems(in: project.id)).value)
        try store.applyScheme(closing, to: project.id, actor: .user)
        #expect(store.items(in: project.id).first { $0.id == epic.id }?.closedAt != nil)

        let backOut = try #require(SchemePlan.plan(
            current: toDone, proposed: .softwareDefault, reassignments: [:],
            items: store.allItems(in: project.id)).value)
        try store.applyScheme(backOut, to: project.id, actor: .user)
        #expect(store.items(in: project.id).first { $0.id == epic.id }?.closedAt == nil)
    }

    @Test("soft-deleted items are reassigned too, so a restore cannot dangle")
    func reassignsDeletedItems() throws {
        let (store, project) = makeStore()
        let epic = try store.createItem(projectID: project.id, parentID: nil, type: .epic,
                                        title: "E", statusID: "in_review", actor: .user)
        try store.deleteItem(epic.id, actor: .user)
        let plan = try #require(planRemovingReview(store, project))

        try store.applyScheme(plan, to: project.id, actor: .user)

        #expect(store.allItems(in: project.id).first { $0.id == epic.id }?.statusID == "todo")
    }

    @Test("the change survives a relaunch")
    func persists() throws {
        let repository = InMemoryProjectRepository()
        let store = ProjectStore(repository: repository)
        let project = store.createProject(name: "Q", kind: .software, actor: .user)
        let plan = try #require(planRemovingReview(store, project))
        try store.applyScheme(plan, to: project.id, actor: .user)

        let reopened = ProjectStore(repository: repository)
        #expect(reopened.openProject(project.id)?.project.statusScheme.status(id: "in_review") == nil)
    }

    @Test("a trashed project is refused")
    func refusesTrashed() throws {
        let (store, project) = makeStore()
        let plan = try #require(planRemovingReview(store, project))
        try store.deleteProject(project.id, actor: .user)

        #expect(throws: QuestError.projectNotFound(project.id)) {
            try store.applyScheme(plan, to: project.id, actor: .user)
        }
    }

    @Test("every item still points at a status that exists")
    func invariantHolds() throws {
        let (store, project) = makeStore()
        let epic = try store.createItem(projectID: project.id, parentID: nil, type: .epic,
                                        title: "E", statusID: "in_review", actor: .user)
        _ = try store.createItem(projectID: project.id, parentID: epic.id, type: .task,
                                 title: "T", statusID: "backlog", actor: .user)
        let plan = try #require(planRemovingReview(store, project))

        try store.applyScheme(plan, to: project.id, actor: .user)

        let scheme = try #require(store.openProject(project.id)?.project.statusScheme)
        for item in store.allItems(in: project.id) {
            #expect(scheme.status(id: item.statusID) != nil)
        }
    }
}
