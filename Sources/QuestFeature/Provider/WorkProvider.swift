import Foundation

/// A project as the provider names it, before Quest has bound anything to it.
public struct RemoteProjectRef: Sendable, Hashable {
    public let key: String
    public let name: String
    public init(key: String, name: String) {
        self.key = key
        self.name = name
    }
}

/// A provider's status, flattened. `isDone` is the only semantics Quest reads —
/// completion follows the done category, never the label text, which is the
/// rule the native scheme already follows.
public struct ProviderStatus: Sendable, Hashable {
    public let id: String
    public let label: String
    public let isDone: Bool
    public init(id: String, label: String, isDone: Bool) {
        self.id = id
        self.label = label
        self.isDone = isDone
    }
}

/// One item the provider says changed. M1 does not consume these; the shape is
/// fixed here so M3's poll loop is a conformance, not a redesign.
public struct ProviderChange: Sendable, Hashable {
    public let itemKey: String
    public let updatedAt: Date
    public init(itemKey: String, updatedAt: Date) {
        self.itemKey = itemKey
        self.updatedAt = updatedAt
    }
}

/// The single field a write moves. Enumerated rather than a dictionary so an
/// adapter cannot silently ignore a field it forgot to map.
public enum ProviderField: Sendable, Hashable {
    case status(String)
    case assignee(String?)
    case dueDate(Date?)
    case title(String)
}

/// The narrow seam every backend sits behind — the three remote adapters in M3
/// and M4, and the native store today. Adapters move canonical fields in and
/// out. They never read the overlay, never touch the UI, never make policy.
public protocol WorkProvider: Sendable {
    var kind: ProviderKind { get }
    func listProjects() async throws -> [RemoteProjectRef]
    func statuses(forProjectKey key: String) async throws -> [ProviderStatus]
    /// Returns what changed plus the cursor to pass next time. A `nil` cursor
    /// in means "everything".
    func changes(forProjectKey key: String, since cursor: String?) async throws
        -> (changes: [ProviderChange], cursor: String?)
    func write(field: ProviderField, itemKey: String) async throws
}
