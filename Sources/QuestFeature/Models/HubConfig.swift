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
    public var bindings: [UUID: ProjectBinding]

    public init() {
        bindings = [:]
    }

    public func binding(for projectID: UUID) -> ProjectBinding? {
        bindings[projectID]
    }

    public mutating func bind(_ projectID: UUID, to binding: ProjectBinding) {
        bindings[projectID] = binding
    }

    public mutating func unbind(_ projectID: UUID) {
        bindings.removeValue(forKey: projectID)
    }

    /// Every project routed to this connection. Knows nothing about trash —
    /// this is routing, not state; the caller decides which ones count.
    public func projectIDs(boundTo connectionID: UUID) -> [UUID] {
        bindings.filter { $0.value.connectionID == connectionID }.map(\.key)
    }
}
