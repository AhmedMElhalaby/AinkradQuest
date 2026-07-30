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
}
