import SwiftUI
import AinkradAppKit

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
        HStack {
            Spacer().frame(width: CGFloat(max(indent, 0)) * 16)
            Button { editing = item } label: {
                Text(item.title).foregroundStyle(theme.tokens.foreground)
            }
            .buttonStyle(.plain)
            Spacer()
            Text(document.project.statusScheme.status(id: item.statusID)?.name ?? item.statusID)
                .font(.caption)
                .foregroundStyle(theme.tokens.accentPrimary)
        }
        .contextMenu {
            Button("Delete", role: .destructive) {
                try? store.deleteItem(item.id, actor: .user)
            }
        }
    }
}
