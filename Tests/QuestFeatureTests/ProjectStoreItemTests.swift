import Testing
import Foundation
@testable import QuestFeature

@MainActor
@Suite("ProjectStore — items")
struct ProjectStoreItemTests {
    private func makeStore() -> (ProjectStore, Project) {
        let store = ProjectStore(repository: InMemoryProjectRepository())
        return (store, store.createProject(name: "Quest", kind: .software, actor: .user))
    }

    @Test("creating an epic stores it at the top level and logs it")
    func createEpic() throws {
        let (store, project) = makeStore()
        let epic = try store.createItem(projectID: project.id, parentID: nil, type: .epic,
                                        title: "M1", statusID: "todo", actor: .agent)

        #expect(store.items(in: project.id).map(\.id) == [epic.id])
        #expect(store.activity(for: project.id).last?.kind == .itemCreated)
        #expect(store.activity(for: project.id).last?.actor == .agent)
    }

    @Test("a subtask three levels deep is allowed, four is refused")
    func depth() throws {
        let (store, project) = makeStore()
        let epic = try store.createItem(projectID: project.id, parentID: nil, type: .epic,
                                        title: "M1", statusID: "todo", actor: .user)
        let item = try store.createItem(projectID: project.id, parentID: epic.id, type: .task,
                                        title: "Task", statusID: "todo", actor: .user)
        let subtask = try store.createItem(projectID: project.id, parentID: item.id, type: .task,
                                           title: "Subtask", statusID: "todo", actor: .user)

        #expect(store.items(in: project.id).count == 3)
        #expect(throws: QuestError.depthExceeded(attempted: 4, maximum: 3)) {
            try store.createItem(projectID: project.id, parentID: subtask.id, type: .task,
                                 title: "Too deep", statusID: "todo", actor: .user)
        }
    }

    @Test("a status outside the project's scheme is refused")
    func unknownStatus() throws {
        let (store, project) = makeStore()
        #expect(throws: QuestError.unknownStatus("shipped")) {
            try store.createItem(projectID: project.id, parentID: nil, type: .epic,
                                 title: "M1", statusID: "shipped", actor: .agent)
        }
    }

    @Test("moving to a done status stamps closedAt; moving back clears it")
    func closedAt() throws {
        let (store, project) = makeStore()
        let epic = try store.createItem(projectID: project.id, parentID: nil, type: .epic,
                                        title: "M1", statusID: "todo", actor: .user)

        try store.setStatus(epic.id, statusID: "done", actor: .user)
        #expect(store.items(in: project.id).first?.closedAt != nil)

        try store.setStatus(epic.id, statusID: "todo", actor: .user)
        #expect(store.items(in: project.id).first?.closedAt == nil)
    }

    @Test("reparenting under a descendant is refused")
    func cycle() throws {
        let (store, project) = makeStore()
        let epic = try store.createItem(projectID: project.id, parentID: nil, type: .epic,
                                        title: "M1", statusID: "todo", actor: .user)
        let item = try store.createItem(projectID: project.id, parentID: epic.id, type: .task,
                                        title: "Task", statusID: "todo", actor: .user)
        let subtask = try store.createItem(projectID: project.id, parentID: item.id, type: .task,
                                           title: "Subtask", statusID: "todo", actor: .user)

        #expect(throws: QuestError.cyclicParent) {
            try store.moveItem(item.id, toParent: subtask.id, orderIndex: 0, actor: .user)
        }
    }

    @Test("deleting an item hides it and its descendants, and restore brings them back")
    func softDelete() throws {
        let (store, project) = makeStore()
        let epic = try store.createItem(projectID: project.id, parentID: nil, type: .epic,
                                        title: "M1", statusID: "todo", actor: .user)
        _ = try store.createItem(projectID: project.id, parentID: epic.id, type: .task,
                                 title: "Child", statusID: "todo", actor: .user)

        try store.deleteItem(epic.id, actor: .agent)
        #expect(store.items(in: project.id).isEmpty)

        try store.restoreItem(epic.id, actor: .user)
        #expect(store.items(in: project.id).count == 2)
    }

    @Test("orderIndex stays unique across siblings even after a delete/restore")
    func orderIndexSurvivesDeleteRestore() throws {
        let (store, project) = makeStore()
        let epic = try store.createItem(projectID: project.id, parentID: nil, type: .epic,
                                        title: "M1", statusID: "todo", actor: .user)
        let first = try store.createItem(projectID: project.id, parentID: epic.id, type: .task,
                                         title: "First", statusID: "todo", actor: .user)
        let second = try store.createItem(projectID: project.id, parentID: epic.id, type: .task,
                                          title: "Second", statusID: "todo", actor: .user)

        try store.deleteItem(second.id, actor: .user)
        let third = try store.createItem(projectID: project.id, parentID: epic.id, type: .task,
                                         title: "Third", statusID: "todo", actor: .user)
        try store.restoreItem(second.id, actor: .user)

        let siblings = store.items(in: project.id).filter { $0.parentID == epic.id }
        #expect(Set(siblings.map(\.orderIndex)).count == siblings.count)
        _ = (first, third)
    }

    @Test("restoring a parent leaves an independently-deleted child in the trash")
    func restoreDoesNotResurrectIndependentlyDeletedDescendant() throws {
        let (store, project) = makeStore()
        let epic = try store.createItem(projectID: project.id, parentID: nil, type: .epic,
                                        title: "M1", statusID: "todo", actor: .user)
        let childA = try store.createItem(projectID: project.id, parentID: epic.id, type: .task,
                                          title: "Child A", statusID: "todo", actor: .user)
        let childB = try store.createItem(projectID: project.id, parentID: epic.id, type: .task,
                                          title: "Child B", statusID: "todo", actor: .user)

        try store.deleteItem(childA.id, actor: .user)
        try store.deleteItem(epic.id, actor: .user)
        try store.restoreItem(epic.id, actor: .user)

        let live = Set(store.items(in: project.id).map(\.id))
        #expect(live.contains(epic.id))
        #expect(live.contains(childB.id))
        #expect(!live.contains(childA.id))
    }

    @Test("restoring a child also restores its trashed ancestors, so it stays reachable")
    func restoreRestoresAncestors() throws {
        let (store, project) = makeStore()
        let epic = try store.createItem(projectID: project.id, parentID: nil, type: .epic,
                                        title: "M1", statusID: "todo", actor: .user)
        let task = try store.createItem(projectID: project.id, parentID: epic.id, type: .task,
                                        title: "Child", statusID: "todo", actor: .user)
        let subtask = try store.createItem(projectID: project.id, parentID: task.id, type: .chore,
                                           title: "Grandchild", statusID: "todo", actor: .user)

        try store.deleteItem(epic.id, actor: .user)
        try store.restoreItem(subtask.id, actor: .user)

        let live = store.items(in: project.id)
        let liveIDs = Set(live.map(\.id))
        #expect(liveIDs.contains(epic.id))
        #expect(liveIDs.contains(task.id))
        #expect(liveIDs.contains(subtask.id))

        // Reachable by walking down from the root epic, which is how every
        // surface renders items.
        let reachable = HierarchyRules.descendants(of: epic.id, in: live).map(\.id)
        #expect(reachable.contains(subtask.id))

        let restoreEvent = store.activity(for: project.id).last
        #expect(restoreEvent?.kind == .itemRestored)
        #expect(restoreEvent?.summary.contains("parent item(s)") == true)
    }

    @Test("updateItem allows plain edits but enforces hierarchy rules on reparent/retype")
    func updateItemValidatesStructuralChanges() throws {
        let (store, project) = makeStore()
        let epic = try store.createItem(projectID: project.id, parentID: nil, type: .epic,
                                        title: "M1", statusID: "todo", actor: .user)
        let item = try store.createItem(projectID: project.id, parentID: epic.id, type: .task,
                                        title: "Task", statusID: "todo", actor: .user)
        let subtask = try store.createItem(projectID: project.id, parentID: item.id, type: .task,
                                           title: "Subtask", statusID: "todo", actor: .user)

        var renamedEpic = epic
        renamedEpic.title = "Renamed"
        try store.updateItem(renamedEpic, actor: .user)
        #expect(store.items(in: project.id).first(where: { $0.id == epic.id })?.title == "Renamed")

        var reparentedEpic = epic
        reparentedEpic.parentID = item.id
        #expect(throws: QuestError.epicMustBeRoot) {
            try store.updateItem(reparentedEpic, actor: .user)
        }

        var cyclicItem = item
        cyclicItem.parentID = subtask.id
        #expect(throws: QuestError.cyclicParent) {
            try store.updateItem(cyclicItem, actor: .user)
        }
    }

    @Test("moveItem does not refuse reparenting onto a soft-deleted epic (known gap, tracked separately)")
    func moveOntoDeletedParentIsNotRefused() throws {
        let (store, project) = makeStore()
        let epic = try store.createItem(projectID: project.id, parentID: nil, type: .epic,
                                        title: "M1", statusID: "todo", actor: .user)
        let other = try store.createItem(projectID: project.id, parentID: nil, type: .epic,
                                         title: "M2", statusID: "todo", actor: .user)
        let item = try store.createItem(projectID: project.id, parentID: other.id, type: .task,
                                        title: "Task", statusID: "todo", actor: .user)
        try store.deleteItem(epic.id, actor: .user)

        try store.moveItem(item.id, toParent: epic.id, orderIndex: 0, actor: .user)

        let live = store.items(in: project.id)
        #expect(live.contains { $0.id == item.id })
        #expect(!live.contains { $0.id == epic.id })
        #expect(live.first { $0.id == item.id }?.parentID == epic.id)
    }
}
