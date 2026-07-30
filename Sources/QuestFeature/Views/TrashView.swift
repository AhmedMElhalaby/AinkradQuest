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
    /// Every failure goes to the shell's single toast path; this view owns no
    /// error string of its own.
    let report: (String, AinkradStatus) -> Void
    /// `.ainkradModal` injects no `DismissAction`, so the presenter — not this
    /// view — owns closing it.
    let onClose: () -> Void

    /// The project awaiting an irreversible purge. Non-nil only while the
    /// confirm dialog is up.
    @State private var pendingPurge: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            header
            if store.trashedProjects.isEmpty && itemEntries.isEmpty {
                AinkradEmptyState(icon: "trash", title: "Trash is empty",
                                  message: "Deleted projects and items appear here until you restore or purge them.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AinkradSpacing.md) {
                        if !store.trashedProjects.isEmpty {
                            AinkradSectionFrame(title: "Projects") {
                                VStack(spacing: AinkradSpacing.xs) {
                                    ForEach(store.trashedProjects) { project in
                                        projectRow(project)
                                    }
                                }
                            }
                        }
                        if !itemEntries.isEmpty {
                            AinkradSectionFrame(title: "Items") {
                                VStack(spacing: AinkradSpacing.xs) {
                                    ForEach(itemEntries) { entry in
                                        itemRow(entry)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        // No padding of its own: `AinkradModalModifier` already applies
        // `.padding(AinkradSpacing.lg)` to its content, so a second one here
        // would double the inset.
        //
        // A deliberate fixed size so the trash does not reflow with the pane
        // behind it. The modifier pads BEFORE it caps (`.padding(.lg)` then
        // `.frame(maxWidth: 480)`), so the content budget is 480 - 2*16 = 448
        // and anything wider has its panel border drawn over the content.
        .frame(width: 440, height: 440)
        // Attached at THIS view's root, not inside a row or the scroll view:
        // the kit dims and centres the dialog within the view it modifies, so
        // an inner attachment would scope the scrim to that inner box.
        .ainkradConfirmDialog(isPresented: Binding(get: { pendingPurge != nil },
                                                   set: { if !$0 { pendingPurge = nil } }),
                              title: "Delete permanently?",
                              // Names the project: this is the one irreversible
                              // action in the app, and "this project" does not
                              // tell you WHICH row's Delete you pressed.
                              message: purgeMessage,
                              confirmTitle: "Delete",
                              isDestructive: true) {
            if let id = pendingPurge { purgeProject(id) }
            pendingPurge = nil
        }
    }

    /// Falls back to the unnamed wording only if the summary has vanished from
    /// under the dialog, which the confirm path never expects.
    private var purgeMessage: String {
        let name = pendingPurge.flatMap { id in store.trashedProjects.first { $0.id == id }?.name }
        guard let name else {
            return "This project and everything in it will be gone for good. This cannot be undone."
        }
        return "“\(name)” and everything in it will be gone for good. This cannot be undone."
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Trash",
                                 subtitle: "Restore an item, or delete it permanently.")
                .frame(maxWidth: .infinity, alignment: .leading)
            AinkradIconButton(systemName: "xmark", action: onClose)
                .help("Close")
                .accessibilityLabel("Close")
        }
    }

    private func projectRow(_ project: ProjectSummary) -> some View {
        AinkradListRow(leading: { AinkradIconGlyph(systemName: project.icon) },
                       title: project.name,
                       subtitle: "Project",
                       trailing: {
                           HStack(spacing: AinkradSpacing.xs) {
                               AinkradButton(title: "Restore", style: .secondary) {
                                   restoreProject(project.id)
                               }
                               // Opens the confirm dialog rather than purging:
                               // the destructive half never fires from one tap.
                               AinkradButton(title: "Delete", style: .danger) {
                                   pendingPurge = project.id
                               }
                           }
                       })
    }

    private func itemRow(_ entry: TrashedItemEntry) -> some View {
        AinkradListRow(leading: { AinkradIconGlyph(systemName: "checklist") },
                       title: entry.label,
                       subtitle: "Work item",
                       trailing: {
                           AinkradButton(title: "Restore", style: .secondary) {
                               restoreItem(entry.id)
                           }
                       })
    }

    /// Items whose project is live AND items whose project is itself trashed
    /// — both must be reachable here, or restoring an item can require first
    /// restoring its project.
    private var itemEntries: [TrashedItemEntry] {
        TrashListing.itemEntries(projects: store.projects, trashedProjects: store.trashedProjects,
                                 allItems: store.allItems(in:))
    }

    /// Restore is the reversible half, so it confirms with a `.success` toast
    /// rather than a dialog.
    private func restoreProject(_ id: UUID) {
        let name = store.trashedProjects.first { $0.id == id }?.name
        run { try store.restoreProject(id, actor: .user) }
            ok: { report(name.map { "Restored \($0)." } ?? "Restored the project.", .success) }
    }

    private func restoreItem(_ id: UUID) {
        run { try store.restoreItem(id, actor: .user) }
            ok: { report("Restored the item.", .success) }
    }

    /// Irreversible, and only ever reached from the confirm dialog above.
    private func purgeProject(_ id: UUID) {
        let name = store.trashedProjects.first { $0.id == id }?.name
        run { try store.purgeProject(id) }
            ok: { report(name.map { "Deleted \($0) permanently." } ?? "Deleted permanently.", .neutral) }
    }

    private func run(_ work: () throws -> Void, ok: () -> Void) {
        do {
            try work()
            ok()
        } catch let failure as QuestError {
            report(failure.message, .danger)
        } catch {
            report(error.localizedDescription, .danger)
        }
    }
}
