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
