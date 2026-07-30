import SwiftUI
import AinkradAppKit

/// The rule an inline row edit must satisfy. Pure so it is testable without a
/// view, and shared with nothing else — an empty title from an inline field is
/// the same mistake `ProjectSidebar.create()` and the settings sheet already
/// guard against, so a row must not be able to lose its name either.
enum InlineEdit {
    static func normalizedTitle(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct ListSurface: View {
    @Bindable var store: ProjectStore
    let document: ProjectDocument
    let theme: HostTheme

    @State private var filter = ItemFilter()
    @State private var sort: ItemSort = .manual
    @State private var editing: WorkItem?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Filter", text: $filter.text).textFieldStyle(.roundedBorder)
                Picker("Sort", selection: $sort) {
                    Text("Manual").tag(ItemSort.manual)
                    Text("Priority").tag(ItemSort.priority)
                    Text("Due").tag(ItemSort.dueDate)
                    Text("Updated").tag(ItemSort.updated)
                    Text("Title").tag(ItemSort.title)
                }
                .frame(width: 160)
                Toggle("Show done", isOn: $filter.includeDone)
            }
            .padding(8)

            List {
                ForEach(epics) { epic in
                    Section {
                        ForEach(descendants(of: epic.id)) { item in
                            row(item, indent: HierarchyRules.depth(of: item.id,
                                                                   in: document.items) - 2)
                        }
                    } header: {
                        header(epic)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .sheet(item: $editing) { item in
            ItemEditor(store: store, document: document, item: item, theme: theme)
        }
    }

    private var epics: [WorkItem] {
        ItemQuery.apply(filter, sort: sort,
                        to: document.items.filter { $0.type == .epic },
                        scheme: document.project.statusScheme)
    }

    private func descendants(of epicID: UUID) -> [WorkItem] {
        ItemQuery.apply(filter, sort: sort,
                        to: HierarchyRules.descendants(of: epicID, in: document.items),
                        scheme: document.project.statusScheme)
    }

    private func header(_ epic: WorkItem) -> some View {
        let progress = EpicProgress.rollup(epicID: epic.id, in: document.items,
                                           scheme: document.project.statusScheme)
        return HStack {
            Text(epic.title).font(.headline)
            Spacer()
            Text("\(progress.done)/\(progress.total)")
                .font(.caption)
                .foregroundStyle(theme.tokens.foreground.opacity(0.7))
        }
        .foregroundStyle(theme.tokens.foreground)
    }

    private func row(_ item: WorkItem, indent: Int) -> some View {
        ListRow(store: store, document: document, item: item, indent: indent, theme: theme,
               openEditor: { editing = item })
        .contextMenu {
            Button("Delete", role: .destructive) {
                try? store.deleteItem(item.id, actor: .user)
            }
        }
    }
}

/// One editable row. A `struct` per row, identified by `item.id` in the
/// `ForEach` above, is how the per-row edit state below stays scoped to that
/// row: SwiftUI keys `@State` to the view's identity, not to the surface, so
/// re-sorting or re-filtering the list never lets one row's in-progress text
/// leak into another — a single `@State` hoisted onto `ListSurface` would not
/// have that property. The title field is seeded from `item.title` only at
/// first appearance of this identity, so a store-driven re-render mid-edit
/// does not clobber what the user is typing; the field commits explicitly on
/// submit or on losing focus, never on every keystroke.
private struct ListRow: View {
    @Bindable var store: ProjectStore
    let document: ProjectDocument
    let item: WorkItem
    let indent: Int
    let theme: HostTheme
    let openEditor: () -> Void

    @State private var title: String
    @State private var errorMessage: String?
    @FocusState private var titleFocused: Bool

    init(store: ProjectStore, document: ProjectDocument, item: WorkItem, indent: Int,
        theme: HostTheme, openEditor: @escaping () -> Void) {
        self.store = store
        self.document = document
        self.item = item
        self.indent = indent
        self.theme = theme
        self.openEditor = openEditor
        _title = State(initialValue: item.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Spacer().frame(width: CGFloat(max(indent, 0)) * 16)
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .foregroundStyle(theme.tokens.foreground)
                    .focused($titleFocused)
                    .onSubmit { commitTitle() }
                    .onChange(of: titleFocused) { wasFocused, isFocused in
                        if wasFocused, !isFocused { commitTitle() }
                    }
                Button("Details", action: openEditor)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(theme.tokens.foreground.opacity(0.7))
                Spacer()
                Picker("Status", selection: statusBinding) {
                    ForEach(document.project.statusScheme.statuses) { status in
                        Text(status.name).tag(status.id)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(theme.statusColors.danger)
            }
        }
        .onChange(of: item.title) { _, newValue in
            // The store, not this field, is the source of truth once the
            // field is not being edited — an external update (e.g. via MCP)
            // must still show up.
            if !titleFocused { title = newValue }
        }
    }

    private var statusBinding: Binding<String> {
        Binding(
            get: { item.statusID },
            set: { newStatusID in
                guard newStatusID != item.statusID else { return }
                do {
                    try store.setStatus(item.id, statusID: newStatusID, actor: .user)
                    errorMessage = nil
                } catch let error as QuestError {
                    errorMessage = error.message
                } catch {
                    errorMessage = error.localizedDescription
                }
            })
    }

    private func commitTitle() {
        guard let normalized = InlineEdit.normalizedTitle(title) else {
            title = item.title
            errorMessage = "Title cannot be empty."
            return
        }
        guard normalized != item.title else { return }
        var updated = item
        updated.title = normalized
        do {
            try store.updateItem(updated, actor: .user)
            errorMessage = nil
        } catch let error as QuestError {
            title = item.title
            errorMessage = error.message
        } catch {
            title = item.title
            errorMessage = error.localizedDescription
        }
    }
}
