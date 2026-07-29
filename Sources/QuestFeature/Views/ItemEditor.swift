import SwiftUI
import AinkradAppKit

/// Shared editor sheet used by every surface that opens a single item.
struct ItemEditor: View {
    @Bindable var store: ProjectStore
    let document: ProjectDocument
    let theme: HostTheme

    @State private var draft: WorkItem
    @State private var hasStartDate: Bool
    @State private var hasDueDate: Bool
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(store: ProjectStore, document: ProjectDocument, item: WorkItem, theme: HostTheme) {
        self.store = store
        self.document = document
        self.theme = theme
        _draft = State(initialValue: item)
        _hasStartDate = State(initialValue: item.startDate != nil)
        _hasDueDate = State(initialValue: item.dueDate != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $draft.title).textFieldStyle(.roundedBorder)
            Picker("Type", selection: $draft.type) {
                ForEach(WorkItemType.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            Picker("Status", selection: $draft.statusID) {
                ForEach(document.project.statusScheme.statuses) { Text($0.name).tag($0.id) }
            }
            Picker("Priority", selection: $draft.priority) {
                ForEach(Priority.allCases, id: \.self) { Text(priorityLabel($0)).tag($0) }
            }

            dateRow(label: "Start", has: $hasStartDate, date: $draft.startDate)
            dateRow(label: "Due", has: $hasDueDate, date: $draft.dueDate)

            TextEditor(text: $draft.body).frame(height: 120)

            if let error {
                Text(error).foregroundStyle(theme.statusColors.danger).font(.caption)
            }

            Divider().overlay(theme.tokens.surface)
            Text("Links").font(.headline).foregroundStyle(theme.tokens.accentPrimary)
            LinkListView(store: store, target: .item(draft.id),
                         links: currentLinks, theme: theme)
            LinkEditor(store: store, target: .item(draft.id), theme: theme)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 460)
        .background(theme.tokens.background)
    }

    private func priorityLabel(_ priority: Priority) -> String {
        switch priority {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .urgent: "Urgent"
        }
    }

    /// A toggle gates each date field so the underlying date stays nil unless
    /// the user explicitly opts in — Timeline's "unscheduled" rail depends on
    /// that nil surviving a trip through the editor untouched.
    @ViewBuilder
    private func dateRow(label: String, has: Binding<Bool>, date: Binding<Date?>) -> some View {
        HStack {
            Toggle("Has \(label.lowercased()) date", isOn: has)
                .onChange(of: has.wrappedValue) { _, newValue in
                    date.wrappedValue = newValue ? (date.wrappedValue ?? Date()) : nil
                }
            if has.wrappedValue {
                DatePicker(label, selection: Binding(
                    get: { date.wrappedValue ?? Date() },
                    set: { date.wrappedValue = $0 }), displayedComponents: .date)
                .labelsHidden()
            }
        }
    }

    /// Read links from the STORE rather than the draft: the link editor commits
    /// immediately through the store, while the rest of this sheet is a draft
    /// saved on Save. Reading the draft would show stale links.
    private var currentLinks: [Link] {
        store.allItems(in: document.project.id).first { $0.id == draft.id }?.links ?? []
    }

    private func save() {
        // The link editor above already committed any link changes directly
        // through the store. draft.links is stale from init time, so pull the
        // store's current copy immediately before saving — otherwise this
        // overwrite would silently delete links added since the sheet opened.
        draft.links = currentLinks
        do {
            try store.updateItem(draft, actor: .user)
            dismiss()
        } catch let failure as QuestError {
            error = failure.message
        } catch {
            self.error = error.localizedDescription
        }
    }
}
