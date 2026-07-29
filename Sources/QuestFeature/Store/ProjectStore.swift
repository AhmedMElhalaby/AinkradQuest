import Foundation
import Observation

/// The single mutation point. Views and MCP operations both go through it, so
/// activity logging and persistence cannot be bypassed by either.
@MainActor
@Observable
public final class ProjectStore {
    /// Live, non-deleted project summaries — what the sidebar renders.
    public private(set) var projects: [ProjectSummary] = []
    /// Soft-deleted projects, restorable from the trash.
    public private(set) var trashedProjects: [ProjectSummary] = []
    /// Set when a write to the repository could not be completed. Views show a
    /// persistent banner while this is non-nil; the in-memory change is kept.
    public private(set) var persistenceFailure: String?

    private let repository: any ProjectRepository
    /// Open documents, cached so repeated reads do not re-decode.
    /// `internal` (not `private`) so Task 7's item API, added as an
    /// `extension ProjectStore` in another file in this module, can reach it.
    var documents: [UUID: ProjectDocument] = [:]
    /// `internal` for the same reason as `documents`.
    var deletedProjectIDs: Set<UUID> = []

    public init(repository: any ProjectRepository) {
        self.repository = repository
        let index = repository.loadIndex()
        let live = index.filter { !$0.isTrashed }.map { summary -> ProjectSummary in
            var summary = summary
            summary.isTrashed = false
            return summary
        }
        let trashed = index.filter { $0.isTrashed }.map { summary -> ProjectSummary in
            var summary = summary
            summary.isTrashed = true
            return summary
        }
        self.projects = live.filter { $0.state != .archived }
            + live.filter { $0.state == .archived }
        self.deletedProjectIDs = Set(trashed.map(\.id))
        self.trashedProjects = trashed
    }

    public var activeProjects: [ProjectSummary] { projects.filter { $0.state == .active } }

    public func projects(inState state: ProjectState) -> [ProjectSummary] {
        projects.filter { $0.state == state }
    }

    public var pausedProjects: [ProjectSummary] { projects(inState: .paused) }
    public var archivedProjects: [ProjectSummary] { projects(inState: .archived) }

    // MARK: reading

    public func openProject(_ id: UUID) -> ProjectDocument? {
        if let cached = documents[id] { return cached }
        guard let loaded = repository.loadProject(id) else { return nil }
        documents[id] = loaded
        return loaded
    }

    public func activity(for id: UUID) -> [ActivityEvent] {
        openProject(id)?.activity ?? []
    }

    // MARK: writing

    @discardableResult
    public func createProject(name: String, kind: ProjectKind,
                              actor: ActivityActor) -> Project {
        let project = Project(id: UUID(), name: name, kind: kind)
        var document = ProjectDocument(project: project)
        document.activity.append(ActivityEvent(projectID: project.id, actor: actor,
                                               kind: .projectCreated,
                                               summary: "created project \(name)"))
        documents[project.id] = document
        persist(document)
        projects.append(project.summary)
        saveIndex()
        return project
    }

    /// `kind`/`summary` let a caller that knows WHAT it changed say so in the
    /// feed — "added link foo" reads better than a generic "updated project".
    public func updateProject(_ project: Project, actor: ActivityActor,
                              kind: ActivityKind = .projectUpdated,
                              summary: String? = nil) throws {
        guard var document = openProject(project.id) else {
            throw QuestError.projectNotFound(project.id)
        }
        var updated = project
        updated.updatedAt = Date()
        document.project = updated
        document.activity.append(ActivityEvent(projectID: updated.id, actor: actor,
                                               kind: kind,
                                               summary: summary ?? "updated project \(updated.name)"))
        commit(document)
    }

    public func archiveProject(_ id: UUID, actor: ActivityActor) throws {
        try setState(id, state: .archived, actor: actor, summary: "archived project")
    }

    /// The general form of `archiveProject`, which stays as a convenience.
    /// Pause exists in the model but had no way to be reached before this.
    public func setState(_ id: UUID, state: ProjectState, actor: ActivityActor,
                         summary: String? = nil) throws {
        guard var document = openProject(id) else { throw QuestError.projectNotFound(id) }
        document.project.state = state
        // archivedAt tracks the archived state rather than accumulating: a
        // project brought back out of the archive is not still archived.
        document.project.archivedAt = state == .archived ? Date() : nil
        document.activity.append(ActivityEvent(projectID: id, actor: actor,
                                               kind: .projectUpdated,
                                               summary: summary ?? "set project state to \(state.rawValue)"))
        commit(document)
    }

    /// Soft. The document stays on disk; only the index entry moves to trash,
    /// so a wrong agent call is one restore away.
    public func deleteProject(_ id: UUID, actor: ActivityActor) throws {
        guard var document = openProject(id) else { throw QuestError.projectNotFound(id) }
        document.activity.append(ActivityEvent(projectID: id, actor: actor,
                                               kind: .projectDeleted,
                                               summary: "moved project to trash"))
        deletedProjectIDs.insert(id)
        commit(document)
    }

    public func restoreProject(_ id: UUID, actor: ActivityActor) throws {
        guard var document = openProject(id) else { throw QuestError.projectNotFound(id) }
        document.activity.append(ActivityEvent(projectID: id, actor: actor,
                                               kind: .projectRestored,
                                               summary: "restored project from trash"))
        deletedProjectIDs.remove(id)
        commit(document)
    }

    // MARK: internals

    /// Writes the document and refreshes the index entry derived from it.
    /// `internal` so the item-level API in Task 7 reuses exactly this path.
    func commit(_ document: ProjectDocument) {
        documents[document.project.id] = document
        persist(document)
        rebuildIndexEntry(for: document.project)
        saveIndex()
    }

    /// Moves the project's summary into whichever of the two owned lists its
    /// trashed state calls for. `trashedProjects` is OWNED state, never derived
    /// from `documents`: after a relaunch no document is open, and rebuilding
    /// the trash from that cache silently dropped every trashed project out of
    /// the index on the next unrelated commit.
    private func rebuildIndexEntry(for project: Project) {
        var summary = project.summary
        summary.updatedAt = Date()
        if deletedProjectIDs.contains(project.id) {
            summary.isTrashed = true
            projects.removeAll { $0.id == project.id }
            if let position = trashedProjects.firstIndex(where: { $0.id == project.id }) {
                trashedProjects[position] = summary
            } else {
                trashedProjects.append(summary)
            }
        } else {
            summary.isTrashed = false
            trashedProjects.removeAll { $0.id == project.id }
            if let position = projects.firstIndex(where: { $0.id == project.id }) {
                projects[position] = summary
            } else {
                projects.append(summary)
            }
        }
    }

    /// Always writes BOTH lists: an entry missing from this array is an entry
    /// gone from disk.
    private func saveIndex() {
        let liveEntries = projects.map { summary -> ProjectSummary in
            var summary = summary
            summary.isTrashed = false
            return summary
        }
        let trashedEntries = trashedProjects.map { summary -> ProjectSummary in
            var summary = summary
            summary.isTrashed = true
            return summary
        }
        do {
            try repository.saveIndex(liveEntries + trashedEntries)
        } catch {
            persistenceFailure = "Could not save the project index. Changes are kept in memory."
        }
    }

    /// A failed write never drops the in-memory change: it is retried once and
    /// then surfaced, because silently losing a typed task is worse than a banner.
    ///
    /// The repository REPORTS failure by throwing. The previous check —
    /// "does `loadProject` still return nil?" — could only ever detect a lost
    /// first write of a brand-new project, because a dropped write to an
    /// existing project still loads the stale document. It also decoded every
    /// item in the project on every commit.
    private func persist(_ document: ProjectDocument) {
        do {
            try repository.saveProject(document)
        } catch {
            do {
                try repository.saveProject(document)
            } catch {
                persistenceFailure = "Could not save \(document.project.name). Changes are kept in memory."
                return
            }
        }
        persistenceFailure = nil
    }
}
