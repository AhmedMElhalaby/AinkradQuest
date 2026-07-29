import Testing
import Foundation
@testable import QuestFeature

@Suite("TimelineLayout")
struct TimelineLayoutTests {
    let projectID = UUID()
    let day = 86_400.0

    private func item(_ title: String, start: Double?, due: Double?) -> WorkItem {
        WorkItem(id: UUID(), projectID: projectID, parentID: UUID(), type: .task,
                 title: title, statusID: "todo",
                 startDate: start.map { Date(timeIntervalSince1970: $0) },
                 dueDate: due.map { Date(timeIntervalSince1970: $0) })
    }

    @Test("overlapping bars get separate lanes; disjoint bars share one")
    func lanes() {
        let result = TimelineLayout.build(items: [
            item("A", start: 0, due: 2 * day),
            item("B", start: day, due: 3 * day),
            item("C", start: 10 * day, due: 11 * day),
        ])

        let lanes = Dictionary(uniqueKeysWithValues: result.bars.map { ($0.title, $0.lane) })
        #expect(lanes["A"] == 0)
        #expect(lanes["B"] == 1)
        #expect(lanes["C"] == 0)
    }

    @Test("an item with only a due date becomes a same-day bar")
    func dueOnly() {
        let result = TimelineLayout.build(items: [item("D", start: nil, due: day)])
        #expect(result.bars.count == 1)
        #expect(result.bars[0].start == result.bars[0].end)
    }

    @Test("dateless items go to the unscheduled rail rather than vanishing")
    func unscheduled() {
        let result = TimelineLayout.build(items: [item("U", start: nil, due: nil)])
        #expect(result.bars.isEmpty)
        #expect(result.unscheduled.map(\.title) == ["U"])
    }
}
