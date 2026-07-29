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
        let live = index.filter { !$0.isTrashed }
        let trashed = index.filter { $0.isTrashed }
        self.projects = live.filter { $0.state != .archived }
            + live.filter { $0.state == .archived }
        self.deletedProjectIDs = Set(trashed.map(\.id))
        self.trashedProjects = trashed
    }

    public var activeProjects: [ProjectSummary] { projects.filter { $0.state == .active } }

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

    public func updateProject(_ project: Project, actor: ActivityActor) throws {
        guard var document = openProject(project.id) else {
            throw QuestError.projectNotFound(project.id)
        }
        var updated = project
        updated.updatedAt = Date()
        document.project = updated
        document.activity.append(ActivityEvent(projectID: updated.id, actor: actor,
                                               kind: .projectUpdated,
                                               summary: "updated project \(updated.name)"))
        commit(document)
    }

    public func archiveProject(_ id: UUID, actor: ActivityActor) throws {
        guard var document = openProject(id) else { throw QuestError.projectNotFound(id) }
        document.project.state = .archived
        document.project.archivedAt = Date()
        document.activity.append(ActivityEvent(projectID: id, actor: actor,
                                               kind: .projectUpdated,
                                               summary: "archived project"))
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

    private func rebuildIndexEntry(for project: Project) {
        var summary = project.summary
        summary.updatedAt = Date()
        if let position = projects.firstIndex(where: { $0.id == project.id }) {
            projects[position] = summary
        } else if !deletedProjectIDs.contains(project.id) {
            projects.append(summary)
        }
        projects.removeAll { deletedProjectIDs.contains($0.id) }
        reloadTrash()
    }

    private func reloadTrash() {
        trashedProjects = deletedProjectIDs.compactMap { documents[$0]?.project.summary }
    }

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
        repository.saveIndex(liveEntries + trashedEntries)
    }

    /// A failed write never drops the in-memory change: it is retried once and
    /// then surfaced, because silently losing a typed task is worse than a banner.
    private func persist(_ document: ProjectDocument) {
        repository.saveProject(document)
        if repository.loadProject(document.project.id) == nil {
            repository.saveProject(document)
            if repository.loadProject(document.project.id) == nil {
                persistenceFailure = "Could not save \(document.project.name). Changes are kept in memory."
                return
            }
        }
        persistenceFailure = nil
    }
}
