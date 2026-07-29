import Foundation

public enum ActivityActor: String, Codable, Sendable { case user, agent }

public enum ActivityKind: String, Codable, Sendable {
    case projectCreated, projectUpdated, projectDeleted, projectRestored
    case itemCreated, itemUpdated, itemMoved, itemStatusChanged
    case itemDeleted, itemRestored
    /// Emitted by `LinkEditor`. `schemeUpdated`/`linkRemoved` were declared for
    /// features that do not ship in M1 (there is no scheme editor and no link
    /// removal), so they are not declared here — an unreachable case in the
    /// feed's switch is a claim the app cannot back up.
    case linkAdded
}

/// Append-only. This is the record that makes full agent control livable: a bad
/// agent call is visible and undoable rather than prevented.
public struct ActivityEvent: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let projectID: UUID
    public let itemID: UUID?
    public let actor: ActivityActor
    public let kind: ActivityKind
    public let summary: String
    public let at: Date

    public init(id: UUID = UUID(), projectID: UUID, itemID: UUID? = nil,
                actor: ActivityActor, kind: ActivityKind, summary: String, at: Date = Date()) {
        self.id = id
        self.projectID = projectID
        self.itemID = itemID
        self.actor = actor
        self.kind = kind
        self.summary = summary
        self.at = at
    }
}
