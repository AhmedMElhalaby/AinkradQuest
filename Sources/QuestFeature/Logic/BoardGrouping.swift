import Foundation

public struct BoardColumn: Sendable, Identifiable {
    public var id: String { status.id }
    public let status: Status
    public let items: [WorkItem]
}

public enum BoardGrouping {
    /// One column per status in scheme order, empty columns included — a board
    /// whose columns appear and disappear with their contents is unusable as a
    /// drop target.
    ///
    /// Epics are excluded: they are containers whose status is derived from
    /// their children, and putting them on the board invites moving a whole
    /// epic by dragging one card.
    public static func columns(items: [WorkItem], scheme: StatusScheme,
                               filter: ItemFilter) -> [BoardColumn] {
        let visible = ItemQuery.apply(filter, sort: .manual,
                                      to: items.filter { $0.type != .epic }, scheme: scheme)
        return scheme.statuses.map { status in
            BoardColumn(status: status, items: visible.filter { $0.statusID == status.id })
        }
    }
}

public struct BoardGroup: Sendable, Identifiable {
    public var id: UUID { epic.id }
    public let epic: WorkItem
    public let columns: [BoardColumn]
}

extension BoardGrouping {
    /// One group per live epic, each carrying the FULL column set for the
    /// scheme — same reasoning as `columns(items:scheme:filter:)`: a column that
    /// vanishes with its contents is useless as a drop target.
    ///
    /// Grouping is by owning EPIC, not by direct parent, so a subtask appears
    /// beside its sibling item rather than in a group of its own. Epics
    /// themselves are still excluded from the columns; they are the group
    /// headers here.
    public static func groupedByEpic(items: [WorkItem], scheme: StatusScheme,
                                     filter: ItemFilter) -> [BoardGroup] {
        let epics = items.filter { $0.type == .epic && !$0.isDeleted }
            .sorted { $0.orderIndex < $1.orderIndex }
        return epics.map { epic in
            let descendants = HierarchyRules.descendants(of: epic.id, in: items)
            return BoardGroup(epic: epic,
                              columns: columns(items: descendants, scheme: scheme,
                                               filter: filter))
        }
    }
}
