import Testing
import Foundation
@testable import QuestFeature

@Suite("Snapshot writer")
struct SnapshotWriterTests {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quest-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSnapshot(taken: Date = Date(timeIntervalSince1970: 1_756_000_000)) -> OverlaySnapshot {
        var overlay = ProjectOverlay(projectID: UUID())
        overlay.notes = "private thinking"
        var map = LinkMap()
        map.link(RemoteRef(connectionID: UUID(), remoteKey: "Q-1"), to: UUID())
        return OverlaySnapshot(takenAt: taken, overlays: [overlay], linkMap: map,
                               migratedRepoProjects: ["a"], migratedBindingProjects: ["b"])
    }

    @Test("a snapshot round-trips through JSON")
    func roundTrip() throws {
        let snapshot = makeSnapshot()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(OverlaySnapshot.self, from: encoder.encode(snapshot))

        #expect(decoded.overlays.first?.notes == "private thinking")
        #expect(decoded.migratedRepoProjects == ["a"])
        #expect(decoded.takenAt == snapshot.takenAt)
        #expect(decoded.version == snapshot.version)
    }

    @Test("the payload is human-readable JSON, not a flat array")
    func readableShape() throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(makeSnapshot())
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // The whole reason the snapshot is plain text is that a person can read
        // it when everything else has failed.
        let root = try #require(object)
        #expect(root["takenAt"] != nil)
        #expect(root["overlays"] is [Any])
    }

    @Test("writing produces a file that can be read back")
    func writeAndRead() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try SnapshotWriter.write(makeSnapshot(), into: directory)

        #expect(FileManager.default.fileExists(atPath: url.path))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let reloaded = try decoder.decode(OverlaySnapshot.self, from: Data(contentsOf: url))
        #expect(reloaded.overlays.first?.notes == "private thinking")
    }

    @Test("writing leaves no temp file behind")
    func noTempResidue() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try SnapshotWriter.write(makeSnapshot(), into: directory)

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        // Atomic write means temp-then-rename; a leftover temp file would
        // accumulate one per snapshot forever.
        #expect(names.allSatisfy { !$0.hasSuffix(".tmp") })
        #expect(names.count == 1)
    }

    @Test("rotation keeps the newest N and deletes the rest")
    func rotation() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var written: [URL] = []
        for offset in 0..<7 {
            let taken = Date(timeIntervalSince1970: 1_756_000_000 + Double(offset) * 3600)
            written.append(try SnapshotWriter.write(makeSnapshot(taken: taken), into: directory))
        }

        let kept = try SnapshotWriter.rotate(in: directory, keeping: 5)

        #expect(kept.count == 5)
        // The two OLDEST are the ones that go.
        #expect(FileManager.default.fileExists(atPath: written[0].path) == false)
        #expect(FileManager.default.fileExists(atPath: written[1].path) == false)
        #expect(FileManager.default.fileExists(atPath: written[6].path))
    }

    @Test("rotation deletes nothing when there are fewer than the limit")
    func rotationUnderLimit() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try SnapshotWriter.write(makeSnapshot(), into: directory)

        let kept = try SnapshotWriter.rotate(in: directory, keeping: 5)

        #expect(kept.count == 1)
    }

    @Test("two snapshots in the same second do not collide")
    func sameSecondFilenames() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let taken = Date(timeIntervalSince1970: 1_756_000_000)

        let first = try SnapshotWriter.write(makeSnapshot(taken: taken), into: directory)
        let second = try SnapshotWriter.write(makeSnapshot(taken: taken), into: directory)

        // A debounce can fire twice in one second. Overwriting silently would
        // mean the rotation holds four distinct snapshots instead of five.
        #expect(first != second)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)
    }
}
