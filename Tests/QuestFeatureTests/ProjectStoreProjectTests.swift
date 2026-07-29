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

    @Test("a soft-deleted project stays trashed across a relaunch")
    func trashSurvivesRelaunch() throws {
        let repository = InMemoryProjectRepository()
        let store = ProjectStore(repository: repository)
        let project = store.createProject(name: "Persisted Oops", kind: .general, actor: .agent)

        try store.deleteProject(project.id, actor: .agent)

        let relaunched = ProjectStore(repository: repository)
        #expect(relaunched.projects.isEmpty)
        #expect(relaunched.trashedProjects.map(\.name) == ["Persisted Oops"])

        try relaunched.restoreProject(project.id, actor: .user)
        #expect(relaunched.projects.map(\.name) == ["Persisted Oops"])
    }

    @Test("a trashed project survives unrelated commits after a relaunch")
    func trashSurvivesUnrelatedCommitsAfterRelaunch() throws {
        let repository = InMemoryProjectRepository()
        let store = ProjectStore(repository: repository)
        let trashed = store.createProject(name: "Trashed A", kind: .general, actor: .user)
        let other = store.createProject(name: "Live B", kind: .general, actor: .user)
        try store.deleteProject(trashed.id, actor: .user)

        // Relaunch: nothing is open, everything comes from the index.
        let relaunched = ProjectStore(repository: repository)
        #expect(relaunched.trashedProjects.map(\.name) == ["Trashed A"])

        // An unrelated write must not evict the trashed project from memory…
        var renamed = other
        renamed.name = "Live B renamed"
        try relaunched.updateProject(renamed, actor: .user)
        #expect(relaunched.trashedProjects.map(\.name) == ["Trashed A"])

        // …nor from the index on disk, even after several more relaunches.
        let again = ProjectStore(repository: repository)
        try again.updateProject(renamed, actor: .user)
        let third = ProjectStore(repository: repository)
        #expect(third.trashedProjects.map(\.name) == ["Trashed A"])
        #expect(third.projects.map(\.name) == ["Live B renamed"])
        #expect(repository.loadIndex().count == 2)

        try third.restoreProject(trashed.id, actor: .user)
        #expect(third.trashedProjects.isEmpty)
        #expect(third.projects.map(\.name).sorted() == ["Live B renamed", "Trashed A"])
    }

    @Test("a dropped save to an ALREADY-CREATED project still surfaces a failure")
    func persistenceFailureOnExistingProject() throws {
        let repository = FailingSaveProjectRepository()
        repository.failSaves = false
        let store = ProjectStore(repository: repository)
        var project = store.createProject(name: "Saved", kind: .general, actor: .user)
        #expect(store.persistenceFailure == nil)

        // The document already exists on disk, so a stale load looks like success.
        repository.failSaves = true
        project.name = "Renamed"
        try store.updateProject(project, actor: .user)

        #expect(store.persistenceFailure != nil)
        #expect(store.projects.map(\.name) == ["Renamed"])

        repository.failSaves = false
        try store.updateProject(project, actor: .user)
        #expect(store.persistenceFailure == nil)
    }

    @Test("a failed save keeps the in-memory change and surfaces persistenceFailure")
    func persistenceFailureSurfaces() {
        let repository = FailingSaveProjectRepository()
        let store = ProjectStore(repository: repository)

        let project = store.createProject(name: "Unsaved", kind: .general, actor: .user)

        #expect(store.projects.map(\.name) == ["Unsaved"])
        #expect(store.persistenceFailure != nil)

        repository.failSaves = false
        try? store.updateProject(project, actor: .user)

        #expect(store.persistenceFailure == nil)
    }

    @Test("a project can be paused and appears only in the paused list")
    func pause() throws {
        let store = ProjectStore(repository: InMemoryProjectRepository())
        let project = store.createProject(name: "Later", kind: .general, actor: .user)

        try store.setState(project.id, state: .paused, actor: .user)

        #expect(store.activeProjects.isEmpty)
        #expect(store.pausedProjects.map(\.name) == ["Later"])
        #expect(store.projects.count == 1)
        #expect(store.openProject(project.id)?.project.state == .paused)
    }

    @Test("state changes are logged with the actor")
    func stateLogged() throws {
        let store = ProjectStore(repository: InMemoryProjectRepository())
        let project = store.createProject(name: "P", kind: .general, actor: .user)

        try store.setState(project.id, state: .archived, actor: .agent)

        let event = store.activity(for: project.id).last
        #expect(event?.kind == .projectUpdated)
        #expect(event?.actor == .agent)
        #expect(store.archivedProjects.map(\.name) == ["P"])
    }

    @Test("state survives a relaunch")
    func statePersists() throws {
        let repository = InMemoryProjectRepository()
        let store = ProjectStore(repository: repository)
        let project = store.createProject(name: "P", kind: .general, actor: .user)
        try store.setState(project.id, state: .paused, actor: .user)

        let reopened = ProjectStore(repository: repository)
        #expect(reopened.pausedProjects.map(\.name) == ["P"])
    }

    @Test("setting a project back to active clears an archive stamp")
    func reactivate() throws {
        let store = ProjectStore(repository: InMemoryProjectRepository())
        let project = store.createProject(name: "P", kind: .general, actor: .user)
        try store.setState(project.id, state: .archived, actor: .user)

        try store.setState(project.id, state: .active, actor: .user)

        #expect(store.activeProjects.map(\.name) == ["P"])
        #expect(store.openProject(project.id)?.project.archivedAt == nil)
    }
}
