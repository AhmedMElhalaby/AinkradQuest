import Foundation

/// The seam M4 replaces. Everything above it — store, views, MCP — is written
/// against this protocol, so repointing Quest at the host-wide Ainkrad content
/// store is a new conformance rather than a rewrite.
public protocol ProjectRepository: AnyObject {
    func loadIndex() -> [ProjectSummary]
    func saveIndex(_ summaries: [ProjectSummary])
    func loadProject(_ id: UUID) -> ProjectDocument?
    func saveProject(_ document: ProjectDocument)
    func removeProject(_ id: UUID)
}

/// Test double. Keeps store tests free of encoding concerns.
public final class InMemoryProjectRepository: ProjectRepository {
    private var index: [ProjectSummary] = []
    private var documents: [UUID: ProjectDocument] = [:]

    public init() {}

    public func loadIndex() -> [ProjectSummary] { index }
    public func saveIndex(_ summaries: [ProjectSummary]) { index = summaries }
    public func loadProject(_ id: UUID) -> ProjectDocument? { documents[id] }
    public func saveProject(_ document: ProjectDocument) { documents[document.project.id] = document }
    public func removeProject(_ id: UUID) { documents.removeValue(forKey: id) }
}
