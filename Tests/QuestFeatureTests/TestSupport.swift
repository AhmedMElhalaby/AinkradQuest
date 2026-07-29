import Foundation
import AinkradAppKit
@testable import QuestFeature

/// An in-memory `PluginDocumentStore`, so repository tests exercise the real
/// encode/decode path without a host.
final class MemoryDocumentStore: PluginDocumentStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    func data(forKey key: String) -> Data? { storage[key] }
    func setData(_ data: Data?, forKey key: String) {
        if let data { storage[key] = data } else { storage.removeValue(forKey: key) }
    }
    var keys: [String] { Array(storage.keys) }
}

/// A `ProjectRepository` whose `saveProject` REPORTS a failed write by
/// throwing, so tests can verify `ProjectStore.persistenceFailure` without
/// touching disk. `loadIndex`/`saveIndex` still work normally; only project
/// persistence fails until `failSaves` is turned off.
struct SaveFailure: Error {}

final class FailingSaveProjectRepository: ProjectRepository {
    private var index: [ProjectSummary] = []
    private var documents: [UUID: ProjectDocument] = [:]
    var failSaves = true

    func loadIndex() -> [ProjectSummary] { index }
    func saveIndex(_ summaries: [ProjectSummary]) { index = summaries }
    func loadProject(_ id: UUID) -> ProjectDocument? { documents[id] }
    func saveProject(_ document: ProjectDocument) throws {
        guard !failSaves else { throw SaveFailure() }
        documents[document.project.id] = document
    }
    func removeProject(_ id: UUID) { documents.removeValue(forKey: id) }
}
