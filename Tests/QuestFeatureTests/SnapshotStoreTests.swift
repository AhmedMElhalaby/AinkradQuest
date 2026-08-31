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

    @Test("restore is refused, not half-applied, when a project's live overlay is corrupt")
    func restoreBlockedByCorruptLiveOverlay() throws {
        let documents = MemoryDocumentStore()
        let corrupt = UUID()
        let healthy = UUID()
        documents.setData(Data("{not json".utf8),
                          forKey: DocumentProjectRepository.overlayKey(corrupt))
        let overlay = OverlayStore(repository: DocumentProjectRepository(documents: documents))
        _ = overlay.overlay(for: corrupt) // triggers the corrupt load
        _ = overlay.update(projectID: healthy) { $0.notes = "should survive untouched" }
        let store = SnapshotStore(overlay: overlay, documents: MemoryDocumentStore(),
                                  projectIDs: { [corrupt, healthy] })

        var restoredHealthy = ProjectOverlay(projectID: healthy)
        restoredHealthy.notes = "from the backup — must NOT land"
        var restoredCorrupt = ProjectOverlay(projectID: corrupt)
        restoredCorrupt.notes = "from the backup"
        let snapshot = OverlaySnapshot(takenAt: Date(timeIntervalSince1970: 1),
                                       overlays: [restoredCorrupt, restoredHealthy],
                                       linkMap: LinkMap(), migratedRepoProjects: [],
                                       migratedBindingProjects: [])

        #expect(throws: SnapshotError.restoreBlocked([corrupt])) {
            try store.apply(snapshot)
        }
        // BLOCKER 3/MAJOR 5: refusing must leave EVERY project exactly as it
        // was — not just the corrupt one — because the failure is detected
        // before the loop starts, so nothing is half-applied.
        #expect(overlay.overlay(for: healthy).notes == "should survive untouched")
    }

    @Test("discarding a corrupt overlay clears the block so a later restore can land")
    func discardThenRestoreSucceeds() throws {
        let documents = MemoryDocumentStore()
        let corrupt = UUID()
        documents.setData(Data("{not json".utf8),
                          forKey: DocumentProjectRepository.overlayKey(corrupt))
        let overlay = OverlayStore(repository: DocumentProjectRepository(documents: documents))
        _ = overlay.overlay(for: corrupt)
        let store = SnapshotStore(overlay: overlay, documents: MemoryDocumentStore(),
                                  projectIDs: { [corrupt] })
        var restored = ProjectOverlay(projectID: corrupt)
        restored.notes = "from the backup"
        let snapshot = OverlaySnapshot(takenAt: Date(timeIntervalSince1970: 1),
                                       overlays: [restored], linkMap: LinkMap(),
                                       migratedRepoProjects: [], migratedBindingProjects: [])

        overlay.removeOverlay(for: corrupt) // the discard action wired in QuestSettingsView
        try store.apply(snapshot)

        #expect(overlay.overlay(for: corrupt).notes == "from the backup")
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

    @Test("a directory with one good snapshot and one garbage file lists both, one restorable one damaged")
    func listingSurfacesDamagedSnapshots() throws {
        let documents = MemoryDocumentStore()
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quest-snap-list-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        do {
            try FolderBookmark.save(folder, forKey: FolderBookmark.vaultRootKey, in: documents)
        } catch {
            // Same sandbox caveat as `FolderBookmarkTests.roundTrip`.
            withKnownIssue("""
                Cannot exercise real security-scoped bookmarks in this test \
                environment: \(error).
                """) {
                throw error
            }
            return
        }

        let snapshotsDir = folder.appendingPathComponent(SnapshotWriter.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)

        let good = OverlaySnapshot(takenAt: Date(timeIntervalSince1970: 1_756_000_000),
                                   overlays: [], linkMap: LinkMap(),
                                   migratedRepoProjects: [], migratedBindingProjects: [])
        try SnapshotWriter.write(good, into: snapshotsDir)

        let garbageName = "quest-overlay-2026-01-01-000000-zzzz.json"
        try Data("not valid json at all".utf8)
            .write(to: snapshotsDir.appendingPathComponent(garbageName))

        let store = SnapshotStore(overlay: makeOverlay(), documents: documents, projectIDs: { [] })
        let entries = store.listSnapshots()

        #expect(entries.count == 2)
        let readable = entries.compactMap { entry -> SnapshotFile? in
            if case .readable(let file) = entry { return file }
            return nil
        }
        let damaged = entries.compactMap { entry -> String? in
            if case .damaged(_, let filename) = entry { return filename }
            return nil
        }
        #expect(readable.count == 1)
        #expect(damaged == [garbageName])
    }
}
