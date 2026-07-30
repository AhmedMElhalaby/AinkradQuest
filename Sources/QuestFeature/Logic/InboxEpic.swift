import Foundation

/// Where a quick capture files itself. Extracted because `TodaySurface` and
/// `ListSurface` each had their own copy and they had already diverged: one
/// filtered soft-deleted epics and created an Inbox, the other fell back to
/// `epics.first` and could file a capture under a soft-deleted epic, where it
/// vanished from every list. Two surfaces disagreeing about where the user's
/// item went is worse than the duplication that caused it.
///
/// Pure and Foundation-only, like its neighbours: it decides, the caller
/// writes. Creation is the caller's job because only it holds the store and
/// the project's opening status.
public enum InboxEpic {
    /// The marker is the epic's title, for now. Renaming the epic therefore
    /// makes the next capture create a second "Inbox" — accepted deliberately;
    /// a real marker field on `WorkItem` is the follow-up.
    public static let title = "Inbox"

    public enum Resolution: Equatable, Sendable {
        /// File under this existing, live Inbox epic.
        case existing(UUID)
        /// No live Inbox epic exists — the caller must create one titled
        /// `InboxEpic.title` at the root. Never "use whatever epic sorts
        /// first": that puts the item somewhere the user did not choose and
        /// would not think to look.
        case create
    }

    /// `items` may include soft-deleted ones (`ProjectDocument.items` does);
    /// deleted epics are ignored, so a trashed Inbox is replaced rather than
    /// swallowing new captures.
    public static func resolve(in items: [WorkItem]) -> Resolution {
        let epics = items.filter { $0.type == .epic && !$0.isDeleted }
        if let inbox = epics.first(where: { $0.title == title }) { return .existing(inbox.id) }
        return .create
    }
}
