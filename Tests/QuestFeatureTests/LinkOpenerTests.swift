import Testing
import Foundation
@testable import QuestFeature

@MainActor
final class RecordingLinkOpener: LinkOpener {
    enum Call: Equatable { case reveal(URL), openFolder(URL), openWeb(URL) }
    var calls: [Call] = []
    var failure: Error?

    func reveal(_ url: URL) throws {
        if let failure { throw failure }
        calls.append(.reveal(url))
    }
    func openFolder(_ url: URL) throws {
        if let failure { throw failure }
        calls.append(.openFolder(url))
    }
    func openWeb(_ url: URL) throws {
        if let failure { throw failure }
        calls.append(.openWeb(url))
    }
}

@MainActor
@Suite("LinkOpening")
struct LinkOpenerTests {
    private func link(_ scheme: LinkScheme, _ identifier: String) -> Link {
        Link(scheme: scheme, identifier: identifier, label: "L")
    }

    @Test("a folder link calls openFolder with that path")
    func folderRoutes() throws {
        let opener = RecordingLinkOpener()
        let reason = try LinkOpening.open(link(.folder, "/tmp/x"), using: opener)
        #expect(reason == nil)
        #expect(opener.calls == [.openFolder(URL(fileURLWithPath: "/tmp/x"))])
    }

    @Test("a file link reveals rather than opens")
    func fileReveals() throws {
        let opener = RecordingLinkOpener()
        _ = try LinkOpening.open(link(.file, "/tmp/x.md"), using: opener)
        #expect(opener.calls == [.reveal(URL(fileURLWithPath: "/tmp/x.md"))])
    }

    @Test("a web link opens on the web")
    func webOpens() throws {
        let opener = RecordingLinkOpener()
        _ = try LinkOpening.open(link(.url, "https://example.com"), using: opener)
        #expect(opener.calls == [.openWeb(URL(string: "https://example.com")!)])
    }

    @Test("an inert link returns its reason and calls nothing")
    func inertDoesNothing() throws {
        let opener = RecordingLinkOpener()
        let reason = try LinkOpening.open(link(.repo, "/tmp/repo"), using: opener)
        #expect(reason?.isEmpty == false)
        #expect(opener.calls.isEmpty)
    }

    @Test("an opener failure propagates rather than being swallowed")
    func failurePropagates() {
        let opener = RecordingLinkOpener()
        opener.failure = LinkOpenError.missingTarget(path: "/tmp/gone")
        #expect(throws: LinkOpenError.missingTarget(path: "/tmp/gone")) {
            _ = try LinkOpening.open(link(.folder, "/tmp/gone"), using: opener)
        }
    }

    @Test("the missing-target error names the path so the message is actionable")
    func missingTargetMessage() {
        #expect(LinkOpenError.missingTarget(path: "/tmp/gone").message.contains("/tmp/gone"))
    }

    @Test("the real opener refuses a path that does not exist")
    func workspaceRefusesMissing() {
        let opener = WorkspaceLinkOpener()
        let ghost = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(throws: LinkOpenError.missingTarget(path: ghost.path)) {
            try opener.openFolder(ghost)
        }
        #expect(throws: LinkOpenError.missingTarget(path: ghost.path)) {
            try opener.reveal(ghost)
        }
    }
}
