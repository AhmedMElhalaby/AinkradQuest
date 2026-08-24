import Testing
import Foundation
@testable import QuestFeature

@MainActor
@Suite("Project binding and repos")
struct ProjectBindingTests {
    private func makeStore() -> ProjectStore { ProjectStore(repository: InMemoryProjectRepository()) }

    @Test("a new project is unbound")
    func defaultsToUnbound() {
        let store = makeStore()
        let project = store.createProject(name: "Quest", kind: .software, actor: .user)
        #expect(project.connectionID == nil)
        #expect(project.repos.isEmpty)
    }

    @Test("binding records the connection and the remote key")
    func bind() throws {
        let store = makeStore()
        let project = store.createProject(name: "Quest", kind: .software, actor: .user)
        let connectionID = UUID()

        try store.bindProject(project.id, to: connectionID, remoteProjectKey: "QST", actor: .user)

        let bound = try #require(store.openProject(project.id)?.project)
        #expect(bound.connectionID == connectionID)
        #expect(bound.remoteProjectKey == "QST")
    }

    @Test("unbinding clears both the connection and the remote key")
    func unbind() throws {
        let store = makeStore()
        let project = store.createProject(name: "Quest", kind: .software, actor: .user)
        try store.bindProject(project.id, to: UUID(), remoteProjectKey: "QST", actor: .user)

        try store.unbindProject(project.id, actor: .user)

        let unbound = try #require(store.openProject(project.id)?.project)
        #expect(unbound.connectionID == nil)
        #expect(unbound.remoteProjectKey == nil)
    }

    @Test("a project attaches several repos, each naming its own connection")
    func multipleRepos() throws {
        let store = makeStore()
        let project = store.createProject(name: "Ainkrad", kind: .software, actor: .user)
        let work = UUID(), personal = UUID()

        try store.attachRepo(AttachedRepo(id: UUID(), connectionID: work,
                                          owner: "acme", name: "api"),
                             to: project.id, actor: .user)
        try store.attachRepo(AttachedRepo(id: UUID(), connectionID: personal,
                                          owner: "AhmedMElhalaby", name: "AinkradQuest"),
                             to: project.id, actor: .user)

        let updated = try #require(store.openProject(project.id)?.project)
        #expect(updated.repos.map(\.slug) == ["acme/api", "AhmedMElhalaby/AinkradQuest"])
        #expect(Set(updated.repos.map(\.connectionID)) == [work, personal])
    }

    @Test("the same repo on the same connection is refused twice")
    func duplicateRepo() throws {
        let store = makeStore()
        let project = store.createProject(name: "Ainkrad", kind: .software, actor: .user)
        let connectionID = UUID()
        try store.attachRepo(AttachedRepo(id: UUID(), connectionID: connectionID,
                                          owner: "a", name: "b"),
                             to: project.id, actor: .user)

        #expect(throws: QuestError.duplicateRepo("a/b")) {
            try store.attachRepo(AttachedRepo(id: UUID(), connectionID: connectionID,
                                              owner: "a", name: "b"),
                                 to: project.id, actor: .user)
        }
    }

    @Test("the same repo slug on a DIFFERENT connection is allowed")
    func sameSlugDifferentConnection() throws {
        let store = makeStore()
        let project = store.createProject(name: "Ainkrad", kind: .software, actor: .user)
        try store.attachRepo(AttachedRepo(id: UUID(), connectionID: UUID(),
                                          owner: "a", name: "b"), to: project.id, actor: .user)
        try store.attachRepo(AttachedRepo(id: UUID(), connectionID: UUID(),
                                          owner: "a", name: "b"), to: project.id, actor: .user)
        #expect(try #require(store.openProject(project.id)?.project).repos.count == 2)
    }

    @Test("detaching removes exactly one repo")
    func detach() throws {
        let store = makeStore()
        let project = store.createProject(name: "Ainkrad", kind: .software, actor: .user)
        let keep = AttachedRepo(id: UUID(), connectionID: UUID(), owner: "a", name: "keep")
        let drop = AttachedRepo(id: UUID(), connectionID: UUID(), owner: "a", name: "drop")
        try store.attachRepo(keep, to: project.id, actor: .user)
        try store.attachRepo(drop, to: project.id, actor: .user)

        try store.detachRepo(drop.id, from: project.id, actor: .user)

        #expect(try #require(store.openProject(project.id)?.project).repos.map(\.name) == ["keep"])
    }

    @Test("detaching an unknown repo throws")
    func detachUnknown() throws {
        let store = makeStore()
        let project = store.createProject(name: "Ainkrad", kind: .software, actor: .user)
        let ghost = UUID()
        #expect(throws: QuestError.repoNotFound(ghost)) {
            try store.detachRepo(ghost, from: project.id, actor: .user)
        }
    }

    @Test("bound projects are counted per connection")
    func countBound() throws {
        let store = makeStore()
        let connectionID = UUID()
        let a = store.createProject(name: "A", kind: .software, actor: .user)
        let b = store.createProject(name: "B", kind: .software, actor: .user)
        _ = store.createProject(name: "C", kind: .software, actor: .user)
        try store.bindProject(a.id, to: connectionID, remoteProjectKey: "A", actor: .user)
        try store.bindProject(b.id, to: connectionID, remoteProjectKey: "B", actor: .user)

        #expect(store.projectCount(boundTo: connectionID) == 2)
        #expect(store.projectCount(boundTo: UUID()) == 0)
    }

    @Test("a project document written before binding existed still loads")
    func lenientDecoding() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Legacy","summaryText":"","icon":"folder",
         "colorToken":"accent","kind":"software","state":"active",
         "statusScheme":\(String(data: try JSONEncoder().encode(StatusScheme.softwareDefault), encoding: .utf8)!),
         "links":[],"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}
        """
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(Project.self, from: Data(json.utf8))
        #expect(project.connectionID == nil)
        #expect(project.repos.isEmpty)
    }
}
