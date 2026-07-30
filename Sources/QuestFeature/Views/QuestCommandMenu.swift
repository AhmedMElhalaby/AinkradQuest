import SwiftUI
import AinkradAppKit

/// ⌘K. Rows come from `CommandCatalog`; this view only filters and dispatches.
struct QuestCommandMenu: View {
    @Bindable var store: ProjectStore
    let hasProject: Bool
    let statuses: [Status]
    let perform: (CommandAction) -> Void

    @State private var query = ""
    @State private var selection: QuestCommand?
    @State private var highlight: Int?

    private var entries: [QuestCommand] {
        CommandCatalog.filtered(
            CommandCatalog.entries(projects: store.projects, hasProject: hasProject,
                                   statuses: statuses),
            query: query)
    }

    var body: some View {
        VStack(spacing: AinkradSpacing.sm) {
            AinkradSearchField(text: $query, placeholder: "Commands")
            AinkradCommandMenu(items: entries,
                               selection: $selection,
                               icon: { $0.icon },
                               label: { $0.title },
                               detail: { $0.detail },
                               highlight: $highlight,
                               handlesKeyPresses: true)
        }
        .padding(AinkradSpacing.md)
        .frame(width: 460)
        .onChange(of: selection) { _, new in
            guard let new else { return }
            selection = nil
            perform(new.action)
        }
    }
}
