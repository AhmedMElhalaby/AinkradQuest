import Foundation

public enum ProjectKind: String, Codable, Sendable { case software, general }
public enum ProjectState: String, Codable, Sendable { case active, paused, archived }

public struct Project: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var summaryText: String
    public var icon: String
    public var colorToken: String
    public var kind: ProjectKind
    public var state: ProjectState
    public var statusScheme: StatusScheme
    public var links: [Link]
    public var createdAt: Date
    public var updatedAt: Date
    public var archivedAt: Date?

    public init(id: UUID, name: String, kind: ProjectKind,
                summaryText: String = "", icon: String = "folder",
                colorToken: String = "accent", state: ProjectState = .active,
                statusScheme: StatusScheme? = nil, links: [Link] = [],
                createdAt: Date = Date(), updatedAt: Date = Date(), archivedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.summaryText = summaryText
        self.icon = icon
        self.colorToken = colorToken
        self.state = state
        self.statusScheme = statusScheme ?? (kind == .software ? .softwareDefault : .generalDefault)
        self.links = links
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
    }

    public var summary: ProjectSummary {
        ProjectSummary(id: id, name: name, icon: icon, colorToken: colorToken,
                       kind: kind, state: state, updatedAt: updatedAt)
    }
}

/// What the index document holds. Deliberately small: the sidebar and
/// Today/Inbox read the index, so it must not require decoding every item.
public struct ProjectSummary: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var icon: String
    public var colorToken: String
    public var kind: ProjectKind
    public var state: ProjectState
    public var updatedAt: Date

    public init(id: UUID, name: String, icon: String, colorToken: String,
                kind: ProjectKind, state: ProjectState, updatedAt: Date) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorToken = colorToken
        self.kind = kind
        self.state = state
        self.updatedAt = updatedAt
    }
}
