import SwiftUI
import UniformTypeIdentifiers
import AinkradAppKit

struct BoardSurface: View {
    @Bindable var store: ProjectStore
    let document: ProjectDocument
    let theme: HostTheme

    @State private var filter = ItemFilter()
    @State private var editing: WorkItem?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(BoardGrouping.columns(items: document.items,
                                              scheme: document.project.statusScheme,
                                              filter: filter)) { column in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(column.status.name)
                            .font(.headline)
                            .foregroundStyle(theme.tokens.foreground)
                        ForEach(column.items) { item in
                            card(item)
                                .draggable(item.id.uuidString)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: 240)
                    .padding(8)
                    .background(theme.tokens.surface)
                    .dropDestination(for: String.self) { payload, _ in
                        guard let raw = payload.first, let id = UUID(uuidString: raw) else {
                            return false
                        }
                        // A rejected status (not in this project's scheme) is
                        // impossible here — the column came from the scheme —
                        // so a throw means a genuinely missing item.
                        do {
                            try store.setStatus(id, statusID: column.status.id, actor: .user)
                            return true
                        } catch { return false }
                    }
                }
            }
            .padding(12)
        }
        .sheet(item: $editing) { item in
            ItemEditor(store: store, document: document, item: item, theme: theme)
        }
    }

    private func card(_ item: WorkItem) -> some View {
        Button { editing = item } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).foregroundStyle(theme.tokens.foreground)
                HStack(spacing: 6) {
                    Text(item.type.rawValue).font(.caption2)
                    ForEach(item.labels, id: \.self) { Text("#\($0)").font(.caption2) }
                }
                .foregroundStyle(theme.tokens.foreground.opacity(0.6))
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.tokens.background)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
