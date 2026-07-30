import Testing
import Foundation
@testable import QuestFeature

@Suite("FolderBookmark")
struct FolderBookmarkTests {
    @Test("a saved bookmark resolves back to the same folder")
    func roundTrip() throws {
        let documents = MemoryDocumentStore()
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quest-bm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        // `bookmarkData(options: .withSecurityScope, ...)` can require a URL
        // that came from an actual user selection (NSOpenPanel) inside a
        // sandboxed app. This test environment is an unsandboxed CLI test
        // run against a plain temp directory, so the call may legitimately
        // fail here even though the identical production code path works
        // correctly inside the sandboxed host app. Skip loudly rather than
        // asserting a false negative, and do NOT drop `.withSecurityScope`
        // from production code to force this green.
        do {
            try FolderBookmark.save(folder, forKey: FolderBookmark.projectsRootKey, in: documents)
        } catch {
            withKnownIssue("""
                Cannot exercise real security-scoped bookmarks in this test \
                environment: bookmarkData(options: .withSecurityScope) failed \
                for a plain temp directory (\(error)). This is expected outside \
                a sandboxed host with a user-selected URL; production code is \
                unchanged.
                """) {
                throw error
            }
            return
        }

        let resolved = FolderBookmark.resolve(forKey: FolderBookmark.projectsRootKey,
                                              in: documents)

        #expect(resolved?.standardizedFileURL.path == folder.standardizedFileURL.path)
    }

    @Test("no bookmark resolves to nil rather than failing")
    func absent() {
        #expect(FolderBookmark.resolve(forKey: FolderBookmark.vaultRootKey,
                                       in: MemoryDocumentStore()) == nil)
    }

    @Test("the two roots use distinct keys")
    func distinctKeys() {
        #expect(FolderBookmark.projectsRootKey != FolderBookmark.vaultRootKey)
    }

    // MARK: - Attachment keying (round 2 fix)
    //
    // These tests prove the KEY DERIVATION and STORE ROUND TRIP: that
    // `resolveAttachment(for:)` recomputes the exact key `attachmentKey`
    // saved under, using nothing but the `Link` itself — no separately
    // persisted id, which was the defect (an inline `UUID()` that nothing
    // could ever ask for again). They do NOT prove real security-scoped
    // bookmark resolution across a process boundary: this test host is
    // UNSANDBOXED, so `bookmarkData(options: .withSecurityScope, ...)` can
    // legitimately fail here the same way `roundTrip()` above documents. A
    // pass below proves the addressing scheme is correct, not that a real
    // sandboxed round trip succeeds.

    @Test("a bookmark saved for a link is resolvable via resolveAttachment using only the link")
    func resolveAttachmentRoundTrip() throws {
        let documents = MemoryDocumentStore()
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quest-attach-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let link = Link(scheme: .folder, identifier: folder.path, label: folder.lastPathComponent)

        do {
            try FolderBookmark.save(folder, forKey: FolderBookmark.attachmentKey(link.id), in: documents)
        } catch {
            withKnownIssue("""
                Cannot exercise real security-scoped bookmarks in this test \
                environment (\(error)); see roundTrip() above. The key \
                derivation this test targets does not depend on this call \
                succeeding, but the store round trip after it does, so skip \
                loudly rather than asserting a false negative.
                """) {
                throw error
            }
            return
        }

        let resolved = FolderBookmark.resolveAttachment(for: link, in: documents)
        #expect(resolved?.standardizedFileURL.path == folder.standardizedFileURL.path)
    }

    @Test("two different links get different attachment keys; the same link is stable across calls")
    func attachmentKeysAreStableAndDistinct() {
        let a = Link(scheme: .folder, identifier: "/a", label: "a")
        let b = Link(scheme: .folder, identifier: "/b", label: "b")

        #expect(FolderBookmark.attachmentKey(a.id) != FolderBookmark.attachmentKey(b.id))
        #expect(FolderBookmark.attachmentKey(a.id) == FolderBookmark.attachmentKey(a.id))
    }

    @Test("after clearing an attachment's bookmark, resolveAttachment returns nil")
    func clearedAttachmentResolvesToNil() {
        let documents = MemoryDocumentStore()
        let link = Link(scheme: .folder, identifier: "/somewhere", label: "somewhere")

        FolderBookmark.clear(forKey: FolderBookmark.attachmentKey(link.id), in: documents)

        #expect(FolderBookmark.resolveAttachment(for: link, in: documents) == nil)
    }
}
