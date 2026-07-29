import Testing
import Foundation
@testable import QuestFeature

@MainActor
@Suite("ProjectStore — links")
struct ProjectStoreLinkTests {
    private func makeStore() -> (ProjectStore, Project) {
        let store = ProjectStore(repository: InMemoryProjectRepository())
        return (store, store.createProject(name: "Quest", kind: .software, actor: .user))
    }

    private let repoLink = Link(scheme: .repo, identifier: "~/Projects/quest", label: "quest")

    @Test("a link added to a project is stored and logged as linkAdded")
    func addToProject() throws {
        let (store, project) = makeStore()
        try store.addLink(to: .project(project.id), link: repoLink, actor: .user)

        #expect(store.openProject(project.id)?.project.links.map(\.label) == ["quest"])
        #expect(store.activity(for: project.id).last?.kind == .linkAdded)
    }

    @Test("a link added to an item is stored on that item and logged against it")
    func addToItem() throws {
        let (store, project) = makeStore()
        let epic = try store.createItem(projectID: project.id, parentID: nil, type: .epic,
                                        title: "M1.1", statusID: "todo", actor: .user)
        let branch = Link(scheme: .branch, identifier: "feature/links",
                          label: "feature/links", repo: "quest")

        try store.addLink(to: .item(epic.id), link: branch, actor: .agent)

        let stored = store.items(in: project.id).first { $0.id == epic.id }
        #expect(stored?.links.first?.repo == "quest")
        let event = store.activity(for: project.id).last
        #expect(event?.kind == .linkAdded)
        #expect(event?.itemID == epic.id)
        #expect(event?.actor == .agent)
    }

    @Test("removing a link drops it and logs linkRemoved")
    func remove() throws {
        let (store, project) = makeStore()
        try store.addLink(to: .project(project.id), link: repoLink, actor: .user)

        try store.removeLink(from: .project(project.id), link: repoLink, actor: .user)

        #expect(store.openProject(project.id)?.project.links.isEmpty == true)
        #expect(store.activity(for: project.id).last?.kind == .linkRemoved)
    }

    @Test("removing a link that is not there throws rather than silently succeeding")
    func removeMissing() throws {
        let (store, project) = makeStore()
        #expect(throws: QuestError.linkNotFound(repoLink.id)) {
            try store.removeLink(from: .project(project.id), link: repoLink, actor: .user)
        }
    }

    @Test("adding a link to a soft-deleted item is refused")
    func refusesTrashedItem() throws {
        let (store, project) = makeStore()
        let epic = try store.createItem(projectID: project.id, parentID: nil, type: .epic,
                                        title: "Gone", statusID: "todo", actor: .user)
        try store.deleteItem(epic.id, actor: .user)

        #expect(throws: QuestError.itemNotFound(epic.id)) {
            try store.addLink(to: .item(epic.id), link: repoLink, actor: .user)
        }
    }

    @Test("an unknown target throws")
    func unknownTarget() {
        let (store, _) = makeStore()
        let ghost = UUID()
        #expect(throws: QuestError.projectNotFound(ghost)) {
            try store.addLink(to: .project(ghost), link: repoLink, actor: .user)
        }
    }
}
