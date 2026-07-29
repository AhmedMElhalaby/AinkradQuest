import Testing
import Foundation
@testable import QuestFeature

@MainActor
@Suite("ProjectStore — projects")
struct ProjectStoreProjectTests {
    private func makeStore() -> ProjectStore { ProjectStore(repository: InMemoryProjectRepository()) }

    @Test("creating a project indexes it and logs the creation")
    func create() {
        let store = makeStore()
        let project = store.createProject(name: "Optimus", kind: .software, actor: .user)

        #expect(store.projects.map(\.name) == ["Optimus"])
        #expect(store.activity(for: project.id).map(\.kind) == [.projectCreated])
    }

    @Test("a software project gets the software scheme")
    func scheme() {
        let store = makeStore()
        let project = store.createProject(name: "Quest", kind: .software, actor: .user)
        #expect(project.statusScheme == .softwareDefault)
    }

    @Test("updating a project persists and logs, recording the actor")
    func update() throws {
        let store = makeStore()
        var project = store.createProject(name: "Old", kind: .general, actor: .user)
        project.name = "New"

        try store.updateProject(project, actor: .agent)

        #expect(store.projects.map(\.name) == ["New"])
        #expect(store.activity(for: project.id).last?.actor == .agent)
    }

    @Test("updating an unknown project throws")
    func updateUnknown() {
        let store = makeStore()
        let ghost = Project(id: UUID(), name: "Ghost", kind: .general)
        #expect(throws: QuestError.projectNotFound(ghost.id)) {
            try store.updateProject(ghost, actor: .user)
        }
    }

    @Test("archiving hides a project from the active list without deleting it")
    func archive() throws {
        let store = makeStore()
        let project = store.createProject(name: "Done", kind: .general, actor: .user)

        try store.archiveProject(project.id, actor: .user)

        #expect(store.activeProjects.isEmpty)
        #expect(store.projects.count == 1)
        #expect(store.openProject(project.id)?.project.state == .archived)
    }

    @Test("deleting is soft and restorable")
    func softDelete() throws {
        let store = makeStore()
        let project = store.createProject(name: "Oops", kind: .general, actor: .agent)

        try store.deleteProject(project.id, actor: .agent)
        #expect(store.projects.isEmpty)
        #expect(store.trashedProjects.map(\.name) == ["Oops"])

        try store.restoreProject(project.id, actor: .user)
        #expect(store.projects.map(\.name) == ["Oops"])
    }
}
