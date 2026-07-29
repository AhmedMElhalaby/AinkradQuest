import Foundation
import AinkradAppKit

/// One JSON document per project plus one index document.
///
/// Leyline persists everything as a single document, which is right for a
/// handful of connections and wrong here: the sidebar and Today/Inbox would
/// have to decode every work item ever written just to draw a list of project
/// names. The index carries exactly what those surfaces need.
public final class DocumentProjectRepository: ProjectRepository {
    private let documents: PluginDocumentStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    static let indexKey = "project-index"
    static func projectKey(_ id: UUID) -> String { "project-\(id.uuidString)" }

    public init(documents: PluginDocumentStore) {
        self.documents = documents
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func loadIndex() -> [ProjectSummary] {
        guard let data = documents.data(forKey: Self.indexKey),
              let summaries = try? decoder.decode([ProjectSummary].self, from: data)
        else { return [] }
        return summaries
    }

    public func saveIndex(_ summaries: [ProjectSummary]) {
        guard let data = try? encoder.encode(summaries) else { return }
        documents.setData(data, forKey: Self.indexKey)
    }

    public func loadProject(_ id: UUID) -> ProjectDocument? {
        guard let data = documents.data(forKey: Self.projectKey(id)),
              let document = try? decoder.decode(ProjectDocument.self, from: data)
        else { return nil }
        return document
    }

    public func saveProject(_ document: ProjectDocument) {
        guard let data = try? encoder.encode(document) else { return }
        documents.setData(data, forKey: Self.projectKey(document.project.id))
    }

    public func removeProject(_ id: UUID) {
        documents.setData(nil, forKey: Self.projectKey(id))
    }
}
