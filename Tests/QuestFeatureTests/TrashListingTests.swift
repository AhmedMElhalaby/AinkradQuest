import Foundation
import Testing
@testable import QuestFeature

@Suite("TrashListing")
struct TrashListingTests {
    private func project(_ name: String, isTrashed: Bool) -> ProjectSummary {
        ProjectSummary(id: UUID(), name: name, icon: "folder", colorToken: "blue",
                       kind: .software, state: .active, updatedAt: Date(), isTrashed: isTrashed)
    }

    private func item(projectID: UUID, title: String, deleted: Bool) -> WorkItem {
        WorkItem(id: UUID(), projectID: projectID, parentID: nil, type: .task,
                title: title, statusID: "todo", deletedAt: deleted ? Date() : nil)
    }

    @Test("a trashed item whose project is still live is listed, unmarked")
    func itemInLiveProject() {
        let live = project("Optimus", isTrashed: false)
        let trashedItem = item(projectID: live.id, title: "Fix login", deleted: true)
        let liveItem = item(projectID: live.id, title: "Ship it", deleted: false)

        let entries = TrashListing.itemEntries(
            projects: [live], trashedProjects: [],
            allItems: { $0 == live.id ? [trashedItem, liveItem] : [] })

        #expect(entries.count == 1)
        #expect(entries[0].id == trashedItem.id)
        #expect(entries[0].label == "Optimus: Fix login")
    }

    @Test("a trashed item whose project is also trashed is still listed, and marked as such")
    func itemInTrashedProjectIsReachable() {
        let trashedProject = project("Legacy", isTrashed: true)
        let trashedItem = item(projectID: trashedProject.id, title: "Old bug", deleted: true)

        let entries = TrashListing.itemEntries(
            projects: [], trashedProjects: [trashedProject],
            allItems: { $0 == trashedProject.id ? [trashedItem] : [] })

        #expect(entries.count == 1)
        #expect(entries[0].id == trashedItem.id)
        #expect(entries[0].label == "Legacy (trashed): Old bug")
    }

    @Test("live items and items in projects with no deletions produce no entries")
    func noFalsePositives() {
        let live = project("Optimus", isTrashed: false)
        let liveItem = item(projectID: live.id, title: "Ship it", deleted: false)

        let entries = TrashListing.itemEntries(
            projects: [live], trashedProjects: [],
            allItems: { $0 == live.id ? [liveItem] : [] })

        #expect(entries.isEmpty)
    }
}
