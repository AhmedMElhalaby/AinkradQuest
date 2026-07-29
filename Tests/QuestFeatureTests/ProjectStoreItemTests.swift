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
}
