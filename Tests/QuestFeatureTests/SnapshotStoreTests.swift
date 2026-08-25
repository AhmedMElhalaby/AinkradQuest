import Testing
import Foundation
@testable import QuestFeature

@MainActor
@Suite("Snapshot store")
struct SnapshotStoreTests {
    private func makeOverlay() -> OverlayStore {
        OverlayStore(repository: InMemoryProjectRepository())
    }

    @Test("with no vault granted, snapshotting reports why rather than failing silently")
    func noGrant() {
        let overlay = makeOverlay()
        let documents = MemoryDocumentStore()
        let store = SnapshotStore(overlay: overlay, documents: documents, projectIDs: { [] })

        let wrote = store.snapshotNow(at: Date(timeIntervalSince1970: 1_756_000_000))

        #expect(wrote == false)
        // A backup that silently does nothing is the worst outcome in this
        // design — the user must be told it is off, not left assuming it works.
        let message = try? #require(store.lastError)
        #expect(message?.isEmpty == false)
        #expect(store.lastSnapshotAt == nil)
    }

    @Test("the grant state is reported for display without acquiring access")
    func grantState() {
        let store = SnapshotStore(overlay: makeOverlay(), documents: MemoryDocumentStore(),
                                  projectIDs: { [] })
        #expect(store.vaultGrant() == .notGranted)
    }

    @Test("a built payload carries every project's overlay and the markers")
    func payloadContents() {
        let overlay = makeOverlay()
        let a = UUID(), b = UUID()
        _ = overlay.update(projectID: a) { $0.notes = "alpha" }
        _ = overlay.update(projectID: b) { $0.notes = "beta" }
        overlay.updateHubConfig {
            $0.markReposMigrated(a)
            $0.bind(b, to: ProjectBinding(connectionID: UUID(), remoteProjectKey: "B"))
        }
        let store = SnapshotStore(overlay: overlay, documents: MemoryDocumentStore(),
                                  projectIDs: { [a, b] })

        let snapshot = store.buildSnapshot(at: Date(timeIntervalSince1970: 1_756_000_000))

        #expect(snapshot.overlays.count == 2)
        #expect(snapshot.migratedRepoProjects.contains(a.uuidString))
        #expect(snapshot.version == OverlaySnapshot.currentVersion)
    }

    @Test("bindings are NOT in the payload")
    func bindingsExcluded() throws {
        let overlay = makeOverlay()
        let projectID = UUID()
        overlay.updateHubConfig {
            $0.bind(projectID, to: ProjectBinding(connectionID: UUID(), remoteProjectKey: "SECRET"))
        }
        let store = SnapshotStore(overlay: overlay, documents: MemoryDocumentStore(),
                                  projectIDs: { [projectID] })

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(store.buildSnapshot(at: Date(timeIntervalSince1970: 1)))
        let text = try #require(String(data: data, encoding: .utf8))

        // Routing is machine-specific: restoring it elsewhere would resurrect
        // bindings to connections that do not exist on that machine.
        #expect(text.contains("SECRET") == false)
    }

    @Test("restoring replaces the live overlay with the snapshot's")
    func restoreReplaces() throws {
        let overlay = makeOverlay()
        let projectID = UUID()
        _ = overlay.update(projectID: projectID) { $0.notes = "current, about to be replaced" }
        let store = SnapshotStore(overlay: overlay, documents: MemoryDocumentStore(),
                                  projectIDs: { [projectID] })

        var restoredOverlay = ProjectOverlay(projectID: projectID)
        restoredOverlay.notes = "from the backup"
        let snapshot = OverlaySnapshot(takenAt: Date(timeIntervalSince1970: 1_756_000_000),
                                       overlays: [restoredOverlay], linkMap: LinkMap(),
                                       migratedRepoProjects: [], migratedBindingProjects: [])

        try store.apply(snapshot)

        #expect(overlay.overlay(for: projectID).notes == "from the backup")
    }

    @Test("restoring a snapshot from a newer Quest is refused, not half-applied")
    func refusesNewerVersion() {
        let overlay = makeOverlay()
        let projectID = UUID()
        _ = overlay.update(projectID: projectID) { $0.notes = "untouched" }
        let store = SnapshotStore(overlay: overlay, documents: MemoryDocumentStore(),
                                  projectIDs: { [projectID] })
        let future = OverlaySnapshot(version: OverlaySnapshot.currentVersion + 1,
                                     takenAt: Date(timeIntervalSince1970: 1),
                                     overlays: [], linkMap: LinkMap(),
                                     migratedRepoProjects: [], migratedBindingProjects: [])

        #expect(throws: SnapshotError.unsupportedVersion(OverlaySnapshot.currentVersion + 1)) {
            try store.apply(future)
        }
        // Refusing must leave the live overlay exactly as it was: a half-applied
        // restore destroys the very data the user was trying to recover.
        #expect(overlay.overlay(for: projectID).notes == "untouched")
    }

    @Test("restoring never writes bindings back")
    func restoreLeavesBindingsAlone() throws {
        let overlay = makeOverlay()
        let projectID = UUID()
        let connectionID = UUID()
        overlay.updateHubConfig {
            $0.bind(projectID, to: ProjectBinding(connectionID: connectionID, remoteProjectKey: "LIVE"))
        }
        let store = SnapshotStore(overlay: overlay, documents: MemoryDocumentStore(),
                                  projectIDs: { [projectID] })
        let snapshot = OverlaySnapshot(takenAt: Date(timeIntervalSince1970: 1),
                                       overlays: [], linkMap: LinkMap(),
                                       migratedRepoProjects: [projectID.uuidString],
                                       migratedBindingProjects: [])

        try store.apply(snapshot)

        // The machine's own routing survives a restore untouched.
        #expect(overlay.hubConfig().binding(for: projectID)?.remoteProjectKey == "LIVE")
        #expect(overlay.hubConfig().hasMigratedRepos(projectID))
    }
}
