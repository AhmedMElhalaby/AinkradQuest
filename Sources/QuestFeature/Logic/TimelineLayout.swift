import Foundation

public struct TimelineBar: Sendable, Identifiable {
    public var id: UUID { itemID }
    public let itemID: UUID
    public let title: String
    public let start: Date
    public let end: Date
    /// Row index. Bars that overlap in time never share a lane.
    public let lane: Int
}

public enum TimelineLayout {
    public struct Result: Sendable {
        public let bars: [TimelineBar]
        /// Items with neither a start nor a due date. They get their own rail
        /// rather than being dropped — a task invisible because nobody dated it
        /// is a task that gets forgotten.
        public let unscheduled: [WorkItem]
    }

    public static func build(items: [WorkItem], scheme: StatusScheme) -> Result {
        let live = items.filter { !$0.isDeleted }
        var unscheduled: [WorkItem] = []
        var dated: [(item: WorkItem, start: Date, end: Date)] = []

        for item in live {
            switch (item.startDate, item.dueDate) {
            case let (start?, due?): dated.append((item, min(start, due), max(start, due)))
            case let (start?, nil): dated.append((item, start, start))
            case let (nil, due?): dated.append((item, due, due))
            case (nil, nil): unscheduled.append(item)
            }
        }

        // Greedy lane packing over start-sorted bars: place each bar in the
        // first lane whose last bar ended before this one starts.
        dated.sort { $0.start < $1.start }
        var laneEnds: [Date] = []
        var bars: [TimelineBar] = []
        for entry in dated {
            let lane = laneEnds.firstIndex { $0 < entry.start } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(entry.end) } else { laneEnds[lane] = entry.end }
            bars.append(TimelineBar(itemID: entry.item.id, title: entry.item.title,
                                    start: entry.start, end: entry.end, lane: lane))
        }
        return Result(bars: bars, unscheduled: unscheduled)
    }
}
