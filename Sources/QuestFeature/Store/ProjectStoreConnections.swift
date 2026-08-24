import Foundation

/// Binding and repo attachment. A separate file per the codebase's habit of
/// one `extension ProjectStore` per concern.
extension ProjectStore {
    public func bindProject(_ id: UUID, to connectionID: UUID,
                            remoteProjectKey: String, actor: ActivityActor) throws {
        guard var project = openProject(id)?.project else { throw QuestError.projectNotFound(id) }
        project.connectionID = connectionID
        project.remoteProjectKey = remoteProjectKey
        try updateProject(project, actor: actor)
    }

    public func unbindProject(_ id: UUID, actor: ActivityActor) throws {
        guard var project = openProject(id)?.project else { throw QuestError.projectNotFound(id) }
        // Both fields clear together: a remote key without a connection names
        // a project on a provider we can no longer reach.
        project.connectionID = nil
        project.remoteProjectKey = nil
        try updateProject(project, actor: actor)
    }

    public func attachRepo(_ repo: AttachedRepo, to projectID: UUID,
                           actor: ActivityActor) throws {
        guard var project = openProject(projectID)?.project else { throw QuestError.projectNotFound(projectID) }
        // Same slug on a DIFFERENT connection is a different repo, so the
        // duplicate check is scoped by connection.
        let clash = project.repos.contains {
            $0.connectionID == repo.connectionID && $0.slug == repo.slug
        }
        guard !clash else { throw QuestError.duplicateRepo(repo.slug) }
        project.repos.append(repo)
        try updateProject(project, actor: actor)
    }

    public func detachRepo(_ repoID: UUID, from projectID: UUID,
                           actor: ActivityActor) throws {
        guard var project = openProject(projectID)?.project else { throw QuestError.projectNotFound(projectID) }
        guard let index = project.repos.firstIndex(where: { $0.id == repoID }) else {
            throw QuestError.repoNotFound(repoID)
        }
        project.repos.remove(at: index)
        try updateProject(project, actor: actor)
    }

    /// The registry refuses to delete a connection projects still use, but it
    /// knows nothing about projects — this is how the caller answers that.
    public func projectCount(boundTo connectionID: UUID) -> Int {
        projects.compactMap { openProject($0.id)?.project }
            .filter { $0.connectionID == connectionID }
            .count
    }

    /// Clears every binding to `connectionID`, across live AND trashed projects.
    ///
    /// Called after a connection is deleted. `projectCount(boundTo:)` counts only
    /// live projects — a connection that can never be deleted because something
    /// sits forgotten in the trash is a worse failure than a stale field — so the
    /// trashed ones are severed here instead. Non-throwing: the connection is
    /// already gone, and refusing to sever would leave worse state than
    /// proceeding. Individual failures surface through `persistenceFailure`.
    public func severBindings(toConnection connectionID: UUID, actor: ActivityActor) {
        let ids = (projects + trashedProjects).map(\.id)
        for id in ids {
            guard var project = openProject(id)?.project,
                  project.connectionID == connectionID
            else { continue }
            // Both fields clear together, the same rule `unbindProject` follows.
            project.connectionID = nil
            project.remoteProjectKey = nil
            try? updateProject(project, actor: actor)
        }
    }
}
