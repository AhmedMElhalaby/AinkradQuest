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
