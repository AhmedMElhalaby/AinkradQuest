import Foundation

public enum WorkItemType: String, Codable, Sendable, CaseIterable {
    case epic, task, bug, story, chore, spike
}

public enum Priority: Int, Codable, Sendable, CaseIterable, Comparable {
    case none = 0, low = 1, medium = 2, high = 3, urgent = 4
    public static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }
}

public struct WorkItem: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let projectID: UUID
    /// Nil means depth 0 — an epic. Enforced by `HierarchyRules`.
    public var parentID: UUID?
    public var type: WorkItemType
    public var title: String
    public var body: String
    public var statusID: String
    public var priority: Priority
    public var labels: [String]
    public var startDate: Date?
    public var dueDate: Date?
    public var orderIndex: Int
    public var links: [Link]
    public var createdAt: Date
    public var updatedAt: Date
    public var closedAt: Date?
    /// Soft delete. Non-nil items are excluded from every surface and query
    /// but remain restorable — this is what makes agent-driven deletes safe.
    public var deletedAt: Date?

    public init(id: UUID, projectID: UUID, parentID: UUID?, type: WorkItemType,
                title: String, statusID: String, body: String = "",
                priority: Priority = .none, labels: [String] = [],
                startDate: Date? = nil, dueDate: Date? = nil, orderIndex: Int = 0,
                links: [Link] = [], createdAt: Date = Date(), updatedAt: Date = Date(),
                closedAt: Date? = nil, deletedAt: Date? = nil) {
        self.id = id
        self.projectID = projectID
        self.parentID = parentID
        self.type = type
        self.title = title
        self.statusID = statusID
        self.body = body
        self.priority = priority
        self.labels = labels
        self.startDate = startDate
        self.dueDate = dueDate
        self.orderIndex = orderIndex
        self.links = links
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.closedAt = closedAt
        self.deletedAt = deletedAt
    }

    public var isDeleted: Bool { deletedAt != nil }
}
