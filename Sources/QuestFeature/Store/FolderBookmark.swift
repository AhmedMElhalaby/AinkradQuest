import Foundation
import AinkradAppKit

/// Security-scoped folder bookmarks, stored in the app's own document store.
///
/// Ainkrad plugins are sandboxed: a path string is not access. This is the same
/// mechanism Lore uses for its vault root (`VaultBookmark`) — a bookmark saved
/// after the user picks a folder, re-resolved on demand, with access started
/// before use.
enum FolderBookmark {
    static let projectsRootKey = "projectsRootBookmark"
    static let vaultRootKey = "vaultRootBookmark"

    /// Key for a bookmark attached to one project's folder link.
    static func attachmentKey(_ id: UUID) -> String { "attachment-\(id.uuidString)" }

    static func save(_ url: URL, forKey key: String, in documents: PluginDocumentStore) throws {
        let data = try url.bookmarkData(options: .withSecurityScope,
                                        includingResourceValuesForKeys: nil, relativeTo: nil)
        documents.setData(data, forKey: key)
    }

    static func resolve(forKey key: String, in documents: PluginDocumentStore) -> URL? {
        guard let data = documents.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        // Lore starts access and does not stop it for the app's lifetime; a
        // scoped resource released while a scan is mid-flight is worse than
        // holding it. Note staleness so a caller can re-ask.
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    static func clear(forKey key: String, in documents: PluginDocumentStore) {
        documents.setData(nil, forKey: key)
    }
}
