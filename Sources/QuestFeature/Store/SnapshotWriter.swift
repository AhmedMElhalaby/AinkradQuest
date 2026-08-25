import Foundation

public enum SnapshotError: Error, Equatable, Sendable {
    case vaultNotGranted
    case vaultUnresolvable(String?)
    case writeFailed(String)
    case unreadable(String)
    case unsupportedVersion(Int)

    /// Written to be read by a person AND by the assistant, matching
    /// `QuestError.message`'s style.
    public var message: String {
        switch self {
        case .vaultNotGranted:
            "Backups are off because no vault folder has been granted. "
                + "Choose one in Quest's settings to start backing up your notes and priorities."
        case .vaultUnresolvable(let path):
            "Your vault folder could not be found"
                + (path.map { " at \($0)" } ?? "")
                + ". Backups have stopped. Grant the folder again in Quest's settings."
        case .writeFailed(let reason):
            "The backup could not be written: \(reason)"
        case .unreadable(let reason):
            "That backup file could not be read: \(reason)"
        case .unsupportedVersion(let version):
            "That backup was written by a newer version of Quest (format \(version)). "
                + "Update Quest to restore it."
        }
    }
}

/// Writes snapshots into the vault, atomically, keeping a bounded rotation.
public enum SnapshotWriter {
    public static let directoryName = "Quest Snapshots"
    public static let keep = 5

    /// Sortable, collision-resistant, and readable in a file listing. The
    /// random suffix exists because a debounce can fire twice within one
    /// second; without it the second write would overwrite the first and the
    /// rotation would hold four distinct snapshots instead of five.
    public static func filename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let suffix = String(UUID().uuidString.prefix(4))
        return "quest-overlay-\(formatter.string(from: date))-\(suffix).json"
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Sorted and pretty-printed on purpose: this file exists to be read by
        // a person when everything else has failed, and a stable key order
        // makes two snapshots diffable.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    @discardableResult
    public static func write(_ snapshot: OverlaySnapshot, into directory: URL) throws -> URL {
        let destination = directory.appendingPathComponent(filename(for: snapshot.takenAt))
        let temporary = destination.appendingPathExtension("tmp")
        do {
            let data = try encoder().encode(snapshot)
            // Temp-then-rename. A crash mid-write must never leave a truncated
            // snapshot in place of a good one: a corrupt backup is worse than a
            // stale one, because it is discovered only when it is needed.
            try data.write(to: temporary, options: .atomic)
            try FileManager.default.moveItem(at: temporary, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw SnapshotError.writeFailed(error.localizedDescription)
        }
    }

    /// Deletes the oldest snapshots beyond `keeping`, newest first by filename.
    ///
    /// Called only AFTER a successful write, so a failed write never costs the
    /// user an existing backup.
    @discardableResult
    public static func rotate(in directory: URL, keeping: Int = keep) throws -> [URL] {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("quest-overlay-") && $0.hasSuffix(".json") }
            .sorted(by: >)
        let urls = names.map { directory.appendingPathComponent($0) }
        for url in urls.dropFirst(keeping) {
            try? FileManager.default.removeItem(at: url)
        }
        return Array(urls.prefix(keeping))
    }
}
