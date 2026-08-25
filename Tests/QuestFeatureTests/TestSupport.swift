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
    private var connections: [Connection] = []
    private var overlays: [UUID: ProjectOverlay] = [:]
    private var linkMap = LinkMap()
    private var hubConfig = HubConfig()
    var failSaves = true

    func loadIndex() -> [ProjectSummary] { index }
    func saveIndex(_ summaries: [ProjectSummary]) { index = summaries }
    func loadProject(_ id: UUID) -> ProjectDocument? { documents[id] }
    func saveProject(_ document: ProjectDocument) throws {
        guard !failSaves else { throw SaveFailure() }
        documents[document.project.id] = document
    }
    func removeProject(_ id: UUID) { documents.removeValue(forKey: id) }
    func loadConnections() -> [Connection] { connections }
    func saveConnections(_ connections: [Connection]) throws {
        guard !failSaves else { throw SaveFailure() }
        self.connections = connections
    }

    func loadOverlay(_ projectID: UUID) -> ProjectOverlay? { overlays[projectID] }
    func saveOverlay(_ overlay: ProjectOverlay) throws {
        guard !failSaves else { throw SaveFailure() }
        overlays[overlay.projectID] = overlay
    }
    func removeOverlay(_ projectID: UUID) { overlays.removeValue(forKey: projectID) }
    func loadLinkMap() -> LinkMap { linkMap }
    func saveLinkMap(_ map: LinkMap) throws {
        guard !failSaves else { throw SaveFailure() }
        linkMap = map
    }
    func loadHubConfig() -> HubConfig { hubConfig }
    func saveHubConfig(_ config: HubConfig) throws {
        guard !failSaves else { throw SaveFailure() }
        hubConfig = config
    }
}

/// A `CredentialStore` whose `setSecret` throws on every deletion (a `nil`
/// secret), so tests can verify a failed Keychain delete surfaces rather than
/// being swallowed. Non-deletion writes still succeed, matching
/// `FailingSaveProjectRepository`'s "only the write under test fails" shape.
final class DeleteFailingCredentialStore: CredentialStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    func secret(forRef ref: String) -> String? { storage[ref] }
    func setSecret(_ secret: String?, forRef ref: String) throws {
        guard let secret else { throw CredentialError.keychain(.delete, errSecIO) }
        storage[ref] = secret
    }
}
