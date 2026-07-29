import SwiftUI
import AinkradAppKit

/// A trashed item to show, with a label that already accounts for whether its
/// parent project is itself trashed — an item's reachability must not depend
/// on the order the user restores things in.
struct TrashedItemEntry: Identifiable {
    let id: UUID
    let label: String
}

/// Pure so it can be pinned by a test without SwiftUI: the item collection
/// for the trash view must cover items whose project is live AND items whose
/// project is also trashed, or a doubly-deleted item becomes unreachable
/// until its project is restored first.
enum TrashListing {
    static func itemEntries(projects: [ProjectSummary], trashedProjects: [ProjectSummary],
                            allItems: (UUID) -> [WorkItem]) -> [TrashedItemEntry] {
        (projects + trashedProjects).flatMap { project in
            allItems(project.id).filter(\.isDeleted).map { item in
                let label = project.isTrashed
                    ? "\(project.name) (trashed): \(item.title)"
                    : "\(project.name): \(item.title)"
                return TrashedItemEntry(id: item.id, label: label)
            }
        }
    }
}

/// The other half of soft delete. Without this view, "restorable" is a claim
/// with no interface behind it — and the MCP deletes are classified on the
/// promise that a person can undo them.
struct TrashView: View {
    @Bindable var store: ProjectStore
    let theme: HostTheme

    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Text(error).font(.caption).foregroundStyle(theme.statusColors.danger)
            }
            Section("Projects") {
                ForEach(store.trashedProjects) { project in
                    HStack {
                        Text(project.name)
                        Spacer()
                        Button("Restore") { restoreProject(project.id) }
                    }
                }
            }
            Section("Items") {
                ForEach(itemEntries) { entry in
                    HStack {
                        Text(entry.label)
                        Spacer()
                        Button("Restore") { restoreItem(entry.id) }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(theme.tokens.foreground)
    }

    /// Items whose project is live AND items whose project is itself trashed
    /// — both must be reachable here, or restoring an item can require first
    /// restoring its project.
    private var itemEntries: [TrashedItemEntry] {
        TrashListing.itemEntries(projects: store.projects, trashedProjects: store.trashedProjects,
                                 allItems: store.allItems(in:))
    }

    private func restoreProject(_ id: UUID) {
        do {
            try store.restoreProject(id, actor: .user)
            error = nil
        } catch let failure as QuestError {
            error = failure.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func restoreItem(_ id: UUID) {
        do {
            try store.restoreItem(id, actor: .user)
            error = nil
        } catch let failure as QuestError {
            error = failure.message
        } catch {
            self.error = error.localizedDescription
        }
    }
}
