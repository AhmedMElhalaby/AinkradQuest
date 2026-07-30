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
    ///
    /// Keyed by the LINK's id (`"scheme:repo#identifier"`, see `Link.id`),
    /// never by a freshly minted `UUID`: a bookmark whose key cannot be
    /// recomputed from the data it belongs to is unreachable by
    /// construction — nothing holds the UUID anywhere else, so nothing could
    /// ever ask for it again. The link id is stable and already unique per
    /// target, so any caller holding the `Link` can derive the same key a
    /// future reader would.
    static func attachmentKey(_ linkID: String) -> String { "attachment-\(linkID)" }

    /// Convenience entry point for a reader that has a `Link` rather than a
    /// bare key — the obvious, correct way to look up an attachment's
    /// bookmark rather than re-deriving `attachmentKey` by hand.
    static func resolveAttachment(for link: Link, in documents: PluginDocumentStore) -> URL? {
        resolve(forKey: attachmentKey(link.id), in: documents)
    }

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
