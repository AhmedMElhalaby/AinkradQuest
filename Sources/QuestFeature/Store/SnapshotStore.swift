import Foundation
import Observation
import AinkradAppKit

/// One snapshot on disk, as the restore list needs to show it.
public struct SnapshotFile: Identifiable, Sendable, Equatable {
    public let url: URL
    public let takenAt: Date
    public let projectCount: Int
    public var id: URL { url }

    public init(url: URL, takenAt: Date, projectCount: Int) {
        self.url = url
        self.takenAt = takenAt
        self.projectCount = projectCount
    }
}

/// One entry in the restore list: a snapshot file that decoded cleanly, or
/// one that is present but unreadable.
///
/// `listSnapshots()` used to silently drop a file it could not decode — which
/// is exactly wrong here: the user reaches this list precisely because
/// something has already gone wrong, and a backup they believe exists
/// vanishing from the UI with no trace is its own failure mode. A damaged
/// entry carries only what is knowable without decoding it (its filename) and
/// is never offerable to `restore(from:)`, which still takes a `SnapshotFile`.
public enum SnapshotEntry: Identifiable, Sendable, Equatable {
    case readable(SnapshotFile)
    /// `url` for identity/display, `filename` for the message — kept
    /// separate so a caller never has to re-derive the name from the URL.
    case damaged(url: URL, filename: String)

    public var id: URL {
        switch self {
        case .readable(let file): file.url
        case .damaged(let url, _): url
        }
    }
}

/// Builds, writes, lists and restores overlay snapshots.
///
/// Every filesystem call goes inside `FolderBookmark.withAccess`, which balances
/// each acquisition with a deferred release. There is deliberately no API here
/// that hands out a resolved, access-started URL.
@MainActor
@Observable
public final class SnapshotStore {
    /// When the last snapshot was successfully written, for the age indicator.
    /// A backup that silently stopped weeks ago is the worst outcome in this
    /// design, so this is surfaced rather than kept internal.
    public private(set) var lastSnapshotAt: Date?
    /// Why the last attempt failed, in `.message` form. Never `localizedDescription`.
    public private(set) var lastError: String?

    private let overlay: OverlayStore
    private let documents: any PluginDocumentStore
    private let projectIDs: () -> [UUID]

    public init(overlay: OverlayStore, documents: any PluginDocumentStore,
                projectIDs: @escaping () -> [UUID]) {
        self.overlay = overlay
        self.documents = documents
        self.projectIDs = projectIDs
    }

    /// Deliberately NOT `public`: `FolderBookmark` is an internal type, and a
    /// public method cannot expose it. Every consumer — the settings view — is
    /// in this module, so internal is sufficient and honest.
    func vaultGrant() -> FolderBookmark.Grant {
        FolderBookmark.grant(forKey: FolderBookmark.vaultRootKey, in: documents)
    }

    /// Collects every project's overlay plus the link map and the migration
    /// markers. Bindings are deliberately excluded — see `OverlaySnapshot`.
    func buildSnapshot(at date: Date) -> OverlaySnapshot {
        let config = overlay.hubConfig()
        let overlays = projectIDs()
            .map { overlay.overlay(for: $0) }
            .filter { !$0.isEmpty }
        return OverlaySnapshot(takenAt: date, overlays: overlays, linkMap: overlay.linkMap(),
                               migratedRepoProjects: config.migratedRepoProjects,
                               migratedBindingProjects: config.migratedBindingProjects)
    }

    /// Writes one snapshot now. Returns whether it was written.
    @discardableResult
    public func snapshotNow(at date: Date = Date()) -> Bool {
        switch vaultGrant() {
        case .notGranted:
            lastError = SnapshotError.vaultNotGranted.message
            return false
        case .unresolvable(let path):
            lastError = SnapshotError.vaultUnresolvable(path).message
            return false
        case .granted:
            break
        }

        let snapshot = buildSnapshot(at: date)
        let written = FolderBookmark.withAccess(forKey: FolderBookmark.vaultRootKey,
                                                in: documents) { root -> Bool in
            do {
                let directory = root.appendingPathComponent(SnapshotWriter.directoryName,
                                                            isDirectory: true)
                try FileManager.default.createDirectory(at: directory,
                                                        withIntermediateDirectories: true)
                try SnapshotWriter.write(snapshot, into: directory)
                // Rotation runs only AFTER a successful write, so a failed
                // write never costs the user an existing backup.
                try SnapshotWriter.rotate(in: directory)
                return true
            } catch let failure as SnapshotError {
                lastError = failure.message
                return false
            } catch {
                lastError = SnapshotError.writeFailed(error.localizedDescription).message
                return false
            }
        }

        guard written == true else {
            if lastError == nil {
                lastError = SnapshotError.vaultUnresolvable(nil).message
            }
            return false
        }
        lastSnapshotAt = date
        lastError = nil
        return true
    }

    public func listSnapshots() -> [SnapshotEntry] {
        FolderBookmark.withAccess(forKey: FolderBookmark.vaultRootKey,
                                  in: documents) { root -> [SnapshotEntry] in
            let directory = root.appendingPathComponent(SnapshotWriter.directoryName,
                                                        isDirectory: true)
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            let entries: [(entry: SnapshotEntry, sortKey: Date)] = names
                .filter { $0.hasPrefix("quest-overlay-") && $0.hasSuffix(".json") }
                .map { name -> (SnapshotEntry, Date) in
                    let url = directory.appendingPathComponent(name)
                    guard let data = try? Data(contentsOf: url),
                          let snapshot = try? decoder.decode(OverlaySnapshot.self, from: data)
                    else {
                        // No `takenAt` to sort by — a damaged file's mtime is
                        // the best available proxy, so it still lands roughly
                        // in place rather than always sorting to one end.
                        let modified = ((try? FileManager.default
                            .attributesOfItem(atPath: url.path))?[.modificationDate] as? Date)
                            ?? Date.distantPast
                        return (.damaged(url: url, filename: name), modified)
                    }
                    let file = SnapshotFile(url: url, takenAt: snapshot.takenAt,
                                            projectCount: snapshot.overlays.count)
                    return (.readable(file), snapshot.takenAt)
                }
            return entries.sorted { $0.sortKey > $1.sortKey }.map(\.entry)
        } ?? []
    }

    public func restore(from file: SnapshotFile) throws {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let snapshot: OverlaySnapshot? = FolderBookmark.withAccess(
            forKey: FolderBookmark.vaultRootKey, in: documents) { _ in
                guard let data = try? Data(contentsOf: file.url) else { return nil }
                return try? decoder.decode(OverlaySnapshot.self, from: data)
            } ?? nil
        guard let snapshot else { throw SnapshotError.unreadable(file.url.lastPathComponent) }
        try apply(snapshot)
    }

    /// Replaces the live overlay with the snapshot's.
    ///
    /// Two guards run FIRST and throw before anything is written, so a
    /// restore never half-applies:
    /// - the version check (a snapshot from a newer Quest is refused outright)
    /// - a scan for any project in the snapshot whose LIVE overlay is
    ///   currently unreadable — writing over corrupt bytes would destroy them,
    ///   and `OverlayStore.update` already refuses that write and returns
    ///   `false`, which used to be silently discarded here (BLOCKER 3):
    ///   `apply` returned normally, the caller reported success, and the
    ///   corrupt project was left exactly as corrupt as before.
    ///
    /// Because every failure is detected before the loop starts, the loop
    /// itself cannot fail partway through — there is no rollback to write
    /// because there is nothing to roll back.
    ///
    /// Bindings are never written back — routing belongs to this machine, not
    /// to the backup.
    func apply(_ snapshot: OverlaySnapshot) throws {
        guard snapshot.version <= OverlaySnapshot.currentVersion else {
            throw SnapshotError.unsupportedVersion(snapshot.version)
        }
        let blocked = snapshot.overlays.map(\.projectID).filter { overlay.isUnreadable($0) }
        guard blocked.isEmpty else {
            throw SnapshotError.restoreBlocked(blocked)
        }
        for overlayDocument in snapshot.overlays {
            overlay.update(projectID: overlayDocument.projectID) { current in
                current = overlayDocument
            }
        }
        overlay.updateLinkMap { $0 = snapshot.linkMap }
        overlay.updateHubConfig { config in
            config.migratedRepoProjects = snapshot.migratedRepoProjects
            config.migratedBindingProjects = snapshot.migratedBindingProjects
        }
    }
}
