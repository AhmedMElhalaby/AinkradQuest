import SwiftUI
import AinkradAppKit

/// Name, summary, icon and colour. Draft-until-Save, like ItemEditor.
struct ProjectSettingsSheet: View {
    @Bindable var store: ProjectStore
    let theme: HostTheme

    @State private var draft: Project
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(store: ProjectStore, project: Project, theme: HostTheme) {
        self.store = store
        self.theme = theme
        _draft = State(initialValue: project)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Name", text: $draft.name)
            TextField("Summary", text: $draft.summaryText)
            TextField("SF Symbol", text: $draft.icon)
            // The kind picker only relabels the project; it does NOT change an
            // existing project's status scheme. Schemes are fixed at creation
            // and are not editable in this milestone — do not read this as a
            // scheme switch.
            Picker("Kind", selection: $draft.kind) {
                Text("Software").tag(ProjectKind.software)
                Text("General").tag(ProjectKind.general)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(theme.statusColors.danger)
            }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(16)
        .frame(width: 420)
        .background(theme.tokens.background)
        .foregroundStyle(theme.tokens.foreground)
    }

    private func save() {
        do {
            try store.updateProject(draft, actor: .user)
            dismiss()
        } catch let failure as QuestError {
            error = failure.message
        } catch {
            self.error = error.localizedDescription
        }
    }
}
