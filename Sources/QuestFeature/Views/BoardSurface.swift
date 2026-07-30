import SwiftUI
import UniformTypeIdentifiers
import AinkradAppKit

struct BoardSurface: View {
    @Bindable var store: ProjectStore
    let document: ProjectDocument
    let report: (String, AinkradStatus) -> Void
    /// Forwarded only because `ItemEditor` is still on its pre-M5 initializer
    /// (Task 12 migrates it), exactly as `OverviewSurface` forwards it for the
    /// link views. Nothing in this file's own layout reads it.
    let theme: HostTheme

    @State private var filter = ItemFilter()
    @State private var editing: WorkItem?
    @State private var groupByEpic = false

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradFormRow(title: "Group by epic") { AinkradToggle(isOn: $groupByEpic) }
                .padding(.horizontal, AinkradSpacing.md)
                .padding(.top, AinkradSpacing.sm)
            ScrollView(.horizontal) {
                if groupByEpic {
                    VStack(alignment: .leading, spacing: AinkradSpacing.lg) {
                        // `groupedByEpic` keeps its orphan backstop: an item
                        // whose epic is gone lands in a trailing "No epic"
                        // group instead of vanishing off the board.
                        ForEach(BoardGrouping.groupedByEpic(items: document.items,
                                                            scheme: document.project.statusScheme,
                                                            filter: filter)) { group in
                            VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
                                AinkradSectionHeader(title: group.epic.title,
                                                     subtitle: group.isOrphanGroup
                                                        ? "Items with no live epic" : nil)
                                columnStrip(group.columns)
                            }
                        }
                    }
                    .padding(AinkradSpacing.md)
                } else {
                    columnStrip(BoardGrouping.columns(items: document.items,
                                                      scheme: document.project.statusScheme,
                                                      filter: filter))
                        .padding(AinkradSpacing.md)
                }
            }
        }
        .animation(AinkradMotion.present, value: groupByEpic)
        // Still a `.sheet`, not `.ainkradModal`: `ItemEditor` dismisses itself
        // through `@Environment(\.dismiss)`, which only a real presentation
        // provides. Task 12 migrates the editor and this presentation together.
        .sheet(item: $editing) { item in
            ItemEditor(store: store, document: document,
                       item: document.items.first { $0.id == item.id } ?? item,
                       theme: theme)
        }
    }

    private func columnStrip(_ columns: [BoardColumn]) -> some View {
        HStack(alignment: .top, spacing: AinkradSpacing.md) {
            ForEach(columns) { column in
                VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
                    HStack {
                        AinkradSectionHeader(title: column.status.name)
                        Spacer()
                        AinkradBadge(text: "\(column.items.count)")
                    }
                    ForEach(column.items) { item in
                        card(item).draggable(item.id.uuidString)
                    }
                    Spacer(minLength: 0)
                }
                // A deliberate fixed column width, so columns stay drop-sized
                // regardless of how much a card's title wants.
                .frame(width: 260)
                .padding(AinkradSpacing.sm)
                .ainkradPanel()
                .dropDestination(for: String.self) { payload, _ in
                    guard let raw = payload.first, let id = UUID(uuidString: raw) else {
                        return false
                    }
                    // A rejected status (not in this project's scheme) is
                    // impossible here — the column came from the scheme —
                    // so a throw means a genuinely missing item. It now
                    // reaches the user instead of being swallowed.
                    do {
                        // `withAnimation` rethrows, so the move and the
                        // animation of its result stay one statement.
                        try withAnimation(AinkradMotion.present) {
                            try store.setStatus(id, statusID: column.status.id, actor: .user)
                        }
                        return true
                    } catch let failure as QuestError {
                        report(failure.message, .danger)
                        return false
                    } catch {
                        report(error.localizedDescription, .danger)
                        return false
                    }
                }
            }
        }
        .animation(AinkradMotion.present, value: columns.flatMap { $0.items.map(\.id) })
    }

    private func card(_ item: WorkItem) -> some View {
        AinkradCard(onTap: { editing = item }) {
            VStack(alignment: .leading, spacing: AinkradSpacing.xs) {
                Text(item.title)
                HStack(spacing: AinkradSpacing.xs) {
                    AinkradBadge(text: item.type.rawValue)
                    ForEach(item.labels, id: \.self) { AinkradChip(label: $0) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
