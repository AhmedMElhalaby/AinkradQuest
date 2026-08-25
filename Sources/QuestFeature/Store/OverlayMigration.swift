import Foundation

/// Moves pre-M2 data out of `ProjectDocument` and into the overlay and hub
/// config, once per project, on first load after upgrading.
///
/// Idempotent by construction: each half checks whether its destination
/// already holds the data before copying. A crash between the halves leaves a
/// partially-migrated project that completes on the next launch rather than
/// duplicating. The legacy fields are deliberately NOT cleared from the
/// document — a rollback to a pre-M2 build must still find them.
public enum OverlayMigration {
    /// Returns whether anything was moved, so a caller can log or count.
    ///
    /// A project whose overlay failed to decode (`OverlayStore` marks it
    /// unreadable) reads back as an EMPTY overlay from `overlay.overlay(for:)`
    /// — indistinguishable here from "nothing migrated yet" — so the repos
    /// half would attempt to move legacy repos into it. `OverlayStore.update`
    /// silently no-ops for an unreadable project (see its `commit` guard), so
    /// that attempt is safely swallowed rather than corrupting anything, but
    /// it also means the repos never actually land: the legacy bytes are
    /// preserved untouched (non-destructive still holds) and the corrupt
    /// overlay must be restored or removed by a human before this project's
    /// repos can complete their move. The hub-config half is unaffected,
    /// since bindings live in a separate document this method does not touch.
    @MainActor
    @discardableResult
    public static func migrateIfNeeded(projectID: UUID,
                                       repository: any ProjectRepository,
                                       overlay: OverlayStore) -> Bool {
        guard let document = repository.loadProject(projectID) else { return false }
        let project = document.project
        var moved = false

        if !project.legacyRepos.isEmpty, overlay.overlay(for: projectID).repos.isEmpty {
            overlay.update(projectID: projectID) { $0.repos = project.legacyRepos }
            moved = true
        }

        if let connectionID = project.legacyConnectionID,
           let key = project.legacyRemoteProjectKey,
           overlay.hubConfig().binding(for: projectID) == nil {
            overlay.updateHubConfig {
                $0.bind(projectID, to: ProjectBinding(connectionID: connectionID,
                                                      remoteProjectKey: key))
            }
            moved = true
        }

        return moved
    }
}
