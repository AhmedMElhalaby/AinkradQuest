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

        let outcome = OverlayMigration.migrateIfNeeded(projectID: projectID,
                                                       repository: repository, overlay: overlay)

        #expect(outcome == .moved)
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
                                                 repository: repository, overlay: overlay) == .moved)
        // Second run must be a no-op, NOT a duplicate append: a crash between
        // the two halves of a migration means this runs again on next launch.
        #expect(OverlayMigration.migrateIfNeeded(projectID: projectID,
                                                 repository: repository, overlay: overlay) == .nothingToDo)
        #expect(overlay.overlay(for: projectID).repos.count == 1)
    }

    @Test("a half-migrated project (repos done, binding pending) completes rather than duplicating")
    func resumesPartialMigrationBindingPending() throws {
        let documents = MemoryDocumentStore()
        let repository = DocumentProjectRepository(documents: documents)
        let projectID = UUID(), connectionID = UUID()
        documents.setData(try legacyDocument(projectID: projectID, connectionID: connectionID),
                          forKey: "project-\(projectID.uuidString)")
        let overlay = OverlayStore(repository: repository)
        // Simulate a crash after the repos half completed (data moved AND
        // marked) but before the binding half ran.
        overlay.update(projectID: projectID) { copy in
            copy.repos = [AttachedRepo(id: UUID(), connectionID: connectionID,
                                       owner: "acme", name: "api")]
        }
        overlay.updateHubConfig { $0.markReposMigrated(projectID) }

        let outcome = OverlayMigration.migrateIfNeeded(projectID: projectID,
                                                       repository: repository, overlay: overlay)

        #expect(outcome == .moved)
        #expect(overlay.overlay(for: projectID).repos.count == 1)
        #expect(overlay.hubConfig().binding(for: projectID)?.remoteProjectKey == "QST")
    }

    /// The mirror of the case above, and the more likely real crash order
    /// since the repos half runs first: binding already migrated and marked,
    /// repos still pending.
    @Test("a half-migrated project (binding done, repos pending) completes rather than duplicating")
    func resumesPartialMigrationReposPending() throws {
        let documents = MemoryDocumentStore()
        let repository = DocumentProjectRepository(documents: documents)
        let projectID = UUID(), connectionID = UUID()
        documents.setData(try legacyDocument(projectID: projectID, connectionID: connectionID),
                          forKey: "project-\(projectID.uuidString)")
        let overlay = OverlayStore(repository: repository)
        // Simulate a crash after the binding half completed but before the
        // repos half ran — the less likely order (repos move first in the
        // real function), but still must resume correctly.
        overlay.updateHubConfig { config in
            config.bind(projectID, to: ProjectBinding(connectionID: connectionID, remoteProjectKey: "QST"))
            config.markBindingMigrated(projectID)
        }

        let outcome = OverlayMigration.migrateIfNeeded(projectID: projectID,
                                                       repository: repository, overlay: overlay)

        #expect(outcome == .moved)
        #expect(overlay.overlay(for: projectID).repos.map(\.slug) == ["acme/api"])
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
                                                 repository: repository, overlay: overlay) == .nothingToDo)
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

    /// Critical: once a half has migrated and marked itself done, a user
    /// deliberately clearing what it moved (unbinding, detaching every repo)
    /// must NOT be reversed by a later launch re-running the migration. The
    /// legacy fields are never cleared (by design, for rollback), so without
    /// a persisted marker this would resurrect the removed data forever.
    @Test("repos removed after migration are not resurrected by a later run")
    func doesNotResurrectRemovedRepos() throws {
        let documents = MemoryDocumentStore()
        let repository = DocumentProjectRepository(documents: documents)
        let projectID = UUID(), connectionID = UUID()
        documents.setData(try legacyDocument(projectID: projectID, connectionID: connectionID),
                          forKey: "project-\(projectID.uuidString)")
        let overlay = OverlayStore(repository: repository)
        #expect(OverlayMigration.migrateIfNeeded(projectID: projectID,
                                                 repository: repository, overlay: overlay) == .moved)

        // The user detaches every repo — clearing the destination by hand.
        overlay.update(projectID: projectID) { $0.repos = [] }

        let outcome = OverlayMigration.migrateIfNeeded(projectID: projectID,
                                                       repository: repository, overlay: overlay)

        #expect(outcome != .moved)
        #expect(overlay.overlay(for: projectID).repos.isEmpty)
    }

    /// Same as above, for the binding half.
    @Test("a binding removed after migration is not resurrected by a later run")
    func doesNotResurrectRemovedBinding() throws {
        let documents = MemoryDocumentStore()
        let repository = DocumentProjectRepository(documents: documents)
        let projectID = UUID(), connectionID = UUID()
        documents.setData(try legacyDocument(projectID: projectID, connectionID: connectionID),
                          forKey: "project-\(projectID.uuidString)")
        let overlay = OverlayStore(repository: repository)
        #expect(OverlayMigration.migrateIfNeeded(projectID: projectID,
                                                 repository: repository, overlay: overlay) == .moved)

        // The user unbinds the project — clearing the destination by hand.
        overlay.updateHubConfig { $0.unbind(projectID) }

        let outcome = OverlayMigration.migrateIfNeeded(projectID: projectID,
                                                       repository: repository, overlay: overlay)

        #expect(outcome != .moved)
        #expect(overlay.hubConfig().binding(for: projectID) == nil)
    }

    /// A project whose overlay is corrupt cannot have its repos written —
    /// `OverlayStore` blocks the write. The migration must report `.blocked`
    /// rather than silently swallowing that and claiming `.moved` (or
    /// marking the repos half done when nothing actually landed), and must
    /// leave the legacy bytes untouched so the move can complete later.
    @Test("a project with an unreadable overlay reports blocked, not moved, for its repos half")
    func reportsBlockedWhenOverlayUnreadable() throws {
        let documents = MemoryDocumentStore()
        let repository = DocumentProjectRepository(documents: documents)
        let projectID = UUID(), connectionID = UUID()
        documents.setData(try legacyDocument(projectID: projectID, connectionID: connectionID),
                          forKey: "project-\(projectID.uuidString)")
        // Corrupt bytes at the overlay key.
        documents.setData(Data("not json".utf8), forKey: "overlay-project-\(projectID.uuidString)")
        let overlay = OverlayStore(repository: repository)

        let outcome = OverlayMigration.migrateIfNeeded(projectID: projectID,
                                                       repository: repository, overlay: overlay)

        #expect(outcome == .blocked)
        // The binding half is unaffected — it lives in a separate document.
        #expect(overlay.hubConfig().binding(for: projectID)?.remoteProjectKey == "QST")
        // Repos were not marked done, so a later run (once the overlay is
        // fixed) will retry rather than skipping forever.
        #expect(!overlay.hubConfig().hasMigratedRepos(projectID))
    }
}
