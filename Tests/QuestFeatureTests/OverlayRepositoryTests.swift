import Testing
import Foundation
@testable import QuestFeature

@Suite("Overlay persistence")
struct OverlayRepositoryTests {
    @Test("an overlay round-trips through the document repository")
    func overlayRoundTrip() throws {
        let documents = MemoryDocumentStore()
        let repository = DocumentProjectRepository(documents: documents)
        let projectID = UUID()
        var overlay = ProjectOverlay(projectID: projectID)
        overlay.notes = "mine"
        try repository.saveOverlay(overlay)

        let reloaded = DocumentProjectRepository(documents: documents)
        #expect(reloaded.loadOverlay(projectID)?.notes == "mine")
    }

    @Test("each project's overlay is its own document")
    func perProjectDocuments() throws {
        let documents = MemoryDocumentStore()
        let repository = DocumentProjectRepository(documents: documents)
        let a = UUID(), b = UUID()
        try repository.saveOverlay(ProjectOverlay(projectID: a))
        try repository.saveOverlay(ProjectOverlay(projectID: b))

        // Per-project, for the same reason ProjectDocument is: the cockpit must
        // not decode every overlay record ever written to draw one project.
        #expect(documents.keys.contains("overlay-project-\(a.uuidString)"))
        #expect(documents.keys.contains("overlay-project-\(b.uuidString)"))
    }

    @Test("a missing overlay loads as nil rather than throwing")
    func missingOverlay() {
        let repository = DocumentProjectRepository(documents: MemoryDocumentStore())
        #expect(repository.loadOverlay(UUID()) == nil)
    }

    @Test("removing an overlay deletes its document")
    func removeOverlay() throws {
        let documents = MemoryDocumentStore()
        let repository = DocumentProjectRepository(documents: documents)
        let projectID = UUID()
        try repository.saveOverlay(ProjectOverlay(projectID: projectID))

        repository.removeOverlay(projectID)

        #expect(repository.loadOverlay(projectID) == nil)
        #expect(documents.keys.contains("overlay-project-\(projectID.uuidString)") == false)
    }

    @Test("the link map round-trips and lives in its own document")
    func linkMapRoundTrip() throws {
        let documents = MemoryDocumentStore()
        let repository = DocumentProjectRepository(documents: documents)
        var map = LinkMap()
        let ref = RemoteRef(connectionID: UUID(), remoteKey: "QST-3")
        let local = UUID()
        map.link(ref, to: local)
        try repository.saveLinkMap(map)

        let reloaded = DocumentProjectRepository(documents: documents)
        #expect(reloaded.loadLinkMap().localID(for: ref) == local)
        #expect(documents.keys.contains("link-map"))
    }

    @Test("hub config round-trips and lives in its own document")
    func hubConfigRoundTrip() throws {
        let documents = MemoryDocumentStore()
        let repository = DocumentProjectRepository(documents: documents)
        var config = HubConfig()
        let projectID = UUID()
        config.bind(projectID, to: ProjectBinding(connectionID: UUID(), remoteProjectKey: "QST"))
        try repository.saveHubConfig(config)

        let reloaded = DocumentProjectRepository(documents: documents)
        #expect(reloaded.loadHubConfig().binding(for: projectID)?.remoteProjectKey == "QST")
        #expect(documents.keys.contains("hub-config"))
    }

    @Test("a missing link map and hub config load empty rather than throwing")
    func missingSingletons() {
        let repository = DocumentProjectRepository(documents: MemoryDocumentStore())
        #expect(repository.loadLinkMap().count == 0)
        #expect(repository.loadHubConfig().bindings.isEmpty)
    }
}
