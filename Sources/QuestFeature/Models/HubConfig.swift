import Foundation

/// Which provider account a project talks to, and what the provider calls it.
public struct ProjectBinding: Codable, Sendable, Hashable {
    public var connectionID: UUID
    public var remoteProjectKey: String

    public init(connectionID: UUID, remoteProjectKey: String) {
        self.connectionID = connectionID
        self.remoteProjectKey = remoteProjectKey
    }
}

/// Routing, deliberately NOT overlay data.
///
/// A binding is not irreplaceable — re-link and it is back — and it is not
/// provider truth either. Keeping it out of the overlay means the backup file
/// carries no routing config, so restoring it on another machine cannot
/// resurrect bindings to connections that do not exist there.
public struct HubConfig: Codable, Sendable {
    /// Keyed by `uuidString`, not `UUID`: this file still gets opened by a
    /// person when something goes wrong — a project bound to the wrong
    /// account, a binding that outlived a delete — and a `[UUID: _]` encodes
    /// as a flat alternating array of keys and values, which is miserable to
    /// read. `ProjectOverlay.items` already keys by `uuidString` for the same
    /// reason; keeping one rule here instead of an exception three files away
    /// costs nothing now and would cost real confusion once this is persisted.
    public var bindings: [String: ProjectBinding]

    public init() {
        bindings = [:]
    }

    public func binding(for projectID: UUID) -> ProjectBinding? {
        bindings[projectID.uuidString]
    }

    public mutating func bind(_ projectID: UUID, to binding: ProjectBinding) {
        bindings[projectID.uuidString] = binding
    }

    public mutating func unbind(_ projectID: UUID) {
        bindings.removeValue(forKey: projectID.uuidString)
    }

    /// Every project routed to this connection. Knows nothing about trash —
    /// this is routing, not state; the caller decides which ones count.
    /// A key that fails to parse as a `UUID` is skipped rather than crashing:
    /// a corrupt row should cost one binding, not the whole config.
    public func projectIDs(boundTo connectionID: UUID) -> [UUID] {
        bindings
            .filter { $0.value.connectionID == connectionID }
            .compactMap { UUID(uuidString: $0.key) }
    }
}
