import Testing
import Foundation
@testable import QuestFeature

@MainActor
@Suite("Overlay migration")
struct OverlayMigrationTests {
    /// A project document in the PRE-M2 shape: repos and binding inside `Project`.
    private func legacyDocument(projectID: UUID, connectionID: UUID) throws -> Data {
        let repoID = UUID()
        let scheme = String(data: try JSONEncoder().encode(StatusScheme.softwareDefault),
                            encoding: .utf8)!
        let json = """
        {"project":{"id":"\(projectID.uuidString)","name":"Legacy","summaryText":"",
          "icon":"folder","colorToken":"accent","kind":"software","state":"active",
          "statusScheme":\(scheme),"links":[],
          "createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z",
          "connectionID":"\(connectionID.uuidString)","remoteProjectKey":"QST",
          "repos":[{"id":"\(repoID.uuidString)","connectionID":"\(connectionID.uuidString)",
                    "owner":"acme","name":"api"}]},
         "items":[],"activity":[]}
        """
        return Data(json.utf8)
    }

    @Test("a pre-M2 document moves its repos and binding into the new stores")
    func migratesLegacyDocument() throws {
        let documents = MemoryDocumentStore()
        let repository = DocumentProjectRepository(documents: documents)
        let projectID = UUID(), connectionID = UUID()
        documents.setData(try legacyDocument(projectID: projectID, connectionID: connectionID),
                          forKey: "project-\(projectID.uuidString)")
        let overlay = OverlayStore(repository: repository)

        let moved = OverlayMigration.migrateIfNeeded(projectID: projectID,
                                                     repository: repository, overlay: overlay)

        #expect(moved)
        #expect(overlay.overlay(for: projectID).repos.map(\.slug) == ["acme/api"])
        #expect(overlay.hubConfig().binding(for: projectID)?.remoteProjectKey == "QST")
        #expect(overlay.hubConfig().binding(for: projectID)?.connectionID == connectionID)
    }

    @Test("migration is idempotent — running it twice moves nothing the second time")
    func idempotent() throws {
        let documents = MemoryDocumentStore()
        let repository = DocumentProjectRepository(documents: documents)
        let projectID = UUID(), connectionID = UUID()
        documents.setData(try legacyDocument(projectID: projectID, connectionID: connectionID),
                          forKey: "project-\(projectID.uuidString)")
        let overlay = OverlayStore(repository: repository)

        #expect(OverlayMigration.migrateIfNeeded(projectID: projectID,
                                                 repository: repository, overlay: overlay))
        // Second run must be a no-op, NOT a duplicate append: a crash between
        // the two halves of a migration means this runs again on next launch.
        #expect(OverlayMigration.migrateIfNeeded(projectID: projectID,
                                                 repository: repository, overlay: overlay) == false)
        #expect(overlay.overlay(for: projectID).repos.count == 1)
    }

    @Test("a half-migrated project completes rather than duplicating")
    func resumesPartialMigration() throws {
        let documents = MemoryDocumentStore()
        let repository = DocumentProjectRepository(documents: documents)
        let projectID = UUID(), connectionID = UUID()
        documents.setData(try legacyDocument(projectID: projectID, connectionID: connectionID),
                          forKey: "project-\(projectID.uuidString)")
        let overlay = OverlayStore(repository: repository)
        // Simulate a crash after the repos moved but before the binding did.
        overlay.update(projectID: projectID) { copy in
            copy.repos = [AttachedRepo(id: UUID(), connectionID: connectionID,
                                       owner: "acme", name: "api")]
        }

        _ = OverlayMigration.migrateIfNeeded(projectID: projectID,
                                             repository: repository, overlay: overlay)

        #expect(overlay.overlay(for: projectID).repos.count == 1)
        #expect(overlay.hubConfig().binding(for: projectID)?.remoteProjectKey == "QST")
    }

    @Test("a project with nothing to migrate reports no work done")
    func nothingToMigrate() throws {
        let documents = MemoryDocumentStore()
        let repository = DocumentProjectRepository(documents: documents)
        let projectID = UUID()
        let document = ProjectDocument(project: Project(id: projectID, name: "Fresh", kind: .general))
        try repository.saveProject(document)
        let overlay = OverlayStore(repository: repository)

        #expect(OverlayMigration.migrateIfNeeded(projectID: projectID,
                                                 repository: repository, overlay: overlay) == false)
    }

    @Test("the legacy fields still decode, so a downgrade does not lose them")
    func legacyFieldsStillDecode() throws {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let projectID = UUID(), connectionID = UUID()
        let data = try legacyDocument(projectID: projectID, connectionID: connectionID)
        let document = try decoder.decode(ProjectDocument.self, from: data)

        // M2 stops WRITING these, but must keep READING them: a user who rolls
        // back to a pre-M2 build must still find their repos in the document.
        #expect(document.project.legacyRepos.count == 1)
        #expect(document.project.legacyConnectionID == connectionID)
        #expect(document.project.legacyRemoteProjectKey == "QST")
    }
}
