import Foundation

/// Binding and repo attachment. A separate file per the codebase's habit of
/// one `extension ProjectStore` per concern.
///
/// M2A moved bindings into `HubConfig` and repos into `ProjectOverlay` — both
/// reached through `self.overlay`, never through `Project.legacyConnectionID`
/// / `.legacyRemoteProjectKey` / `.legacyRepos`, which new code only reads for
/// migration and never writes.
extension ProjectStore {
    public func bindProject(_ id: UUID, to connectionID: UUID,
                            remoteProjectKey: String, actor: ActivityActor) throws {
        guard openProject(id) != nil else { throw QuestError.projectNotFound(id) }
        overlay.updateHubConfig {
            $0.bind(id, to: ProjectBinding(connectionID: connectionID,
                                           remoteProjectKey: remoteProjectKey))
        }
        bumpRevision()
    }

    public func unbindProject(_ id: UUID, actor: ActivityActor) throws {
        guard openProject(id) != nil else { throw QuestError.projectNotFound(id) }
        // Both fields clear together: a remote key without a connection names
        // a project on a provider we can no longer reach.
        overlay.updateHubConfig { $0.unbind(id) }
        bumpRevision()
    }

    public func attachRepo(_ repo: AttachedRepo, to projectID: UUID,
                           actor: ActivityActor) throws {
        guard openProject(projectID) != nil else { throw QuestError.projectNotFound(projectID) }
        // Same slug on a DIFFERENT connection is a different repo, so the
        // duplicate check is scoped by connection.
        let existing = overlay.overlay(for: projectID).repos
        let clash = existing.contains {
            $0.connectionID == repo.connectionID && $0.slug == repo.slug
        }
        guard !clash else { throw QuestError.duplicateRepo(repo.slug) }
        overlay.update(projectID: projectID) { $0.repos.append(repo) }
        bumpRevision()
    }

    public func detachRepo(_ repoID: UUID, from projectID: UUID,
                           actor: ActivityActor) throws {
        guard openProject(projectID) != nil else { throw QuestError.projectNotFound(projectID) }
        let existing = overlay.overlay(for: projectID).repos
        guard existing.contains(where: { $0.id == repoID }) else {
            throw QuestError.repoNotFound(repoID)
        }
        overlay.update(projectID: projectID) { current in
            current.repos.removeAll { $0.id == repoID }
        }
        bumpRevision()
    }

    /// The registry refuses to delete a connection projects still use, but it
    /// knows nothing about projects — this is how the caller answers that.
    public func projectCount(boundTo connectionID: UUID) -> Int {
        projects
            .filter { overlay.hubConfig().binding(for: $0.id)?.connectionID == connectionID }
            .count
    }

    /// Clears every binding to `connectionID`, across live AND trashed projects.
    ///
    /// Called after a connection is deleted. `projectCount(boundTo:)` counts only
    /// live projects — a connection that can never be deleted because something
    /// sits forgotten in the trash is a worse failure than a stale field — so the
    /// trashed ones are severed here instead. Non-throwing: the connection is
    /// already gone, and refusing to sever would leave worse state than
    /// proceeding. `HubConfig.unbind` cannot fail, unlike the old per-document
    /// write, so there is no `persistenceFailure` path to surface per project
    /// here — a failed `updateHubConfig` save still raises `overlay.persistenceFailure`.
    public func severBindings(toConnection connectionID: UUID, actor: ActivityActor) {
        let ids = (projects + trashedProjects).map(\.id)
            .filter { overlay.hubConfig().binding(for: $0)?.connectionID == connectionID }
        guard !ids.isEmpty else { return }
        overlay.updateHubConfig { config in
            for id in ids { config.unbind(id) }
        }
        bumpRevision()
    }
}
