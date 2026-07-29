import Testing
import Foundation
@testable import QuestFeature

@Suite("BoardGrouping")
struct BoardGroupingTests {
    let projectID = UUID()

    private func item(_ title: String, status: String) -> WorkItem {
        WorkItem(id: UUID(), projectID: projectID, parentID: UUID(), type: .task,
                 title: title, statusID: status)
    }

    @Test("columns follow scheme order, including empty ones")
    func columnOrder() {
        let columns = BoardGrouping.columns(items: [item("A", status: "done")],
                                            scheme: .softwareDefault, filter: ItemFilter())
        #expect(columns.map(\.status.id) == ["backlog", "todo", "in_progress", "in_review", "done"])
        #expect(columns.last?.items.map(\.title) == ["A"])
        #expect(columns.first?.items.isEmpty == true)
    }

    @Test("an item whose status is not in the scheme is dropped rather than crashing")
    func orphanStatus() throws {
        let columns = BoardGrouping.columns(items: [item("Orphan", status: "ghost")],
                                            scheme: .softwareDefault, filter: ItemFilter())
        try #expect(columns.allSatisfy(\.items.isEmpty))
    }

    @Test("epics are excluded — the board shows work, not containers")
    func epicsExcluded() throws {
        let epic = WorkItem(id: UUID(), projectID: projectID, parentID: nil, type: .epic,
                            title: "E", statusID: "todo")
        let columns = BoardGrouping.columns(items: [epic], scheme: .softwareDefault,
                                            filter: ItemFilter())
        try #expect(columns.allSatisfy(\.items.isEmpty))
    }
}
