import SwiftUI
import AinkradAppKit

/// Which projects the sidebar lists. `all` exists so no state can strand a
/// project out of reach — the bug this filter was added to fix.
public enum ProjectStateFilter: String, CaseIterable, Identifiable, Sendable {
    case active, paused, archived, all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .active: "Active"
        case .paused: "Paused"
        case .archived: "Archived"
        case .all: "All"
        }
    }

    public func apply(to summaries: [ProjectSummary]) -> [ProjectSummary] {
        switch self {
        case .all: summaries
        case .active: summaries.filter { $0.state == .active }
        case .paused: summaries.filter { $0.state == .paused }
        case .archived: summaries.filter { $0.state == .archived }
        }
    }
}

/// Wraps a freshly created project's attachment suggestions for `.sheet(item:)`,
/// which needs `Identifiable` rather than a bare tuple.
private struct SuggestionSheetState: Identifiable {
    let projectID: UUID
    let suggestions: [AttachmentSuggestion]
    var id: UUID { projectID }
}

struct ProjectSidebar: View {
    @Bindable var store: ProjectStore
    let theme: HostTheme
    let documents: PluginDocumentStore
    @Binding var selection: UUID?
    @Binding var surface: QuestSurface
    @Binding var showingTrash: Bool
    @Binding var settingsProject: UUID?

    @State private var newProjectName = ""
    @State private var filter: ProjectStateFilter = .active
    @State private var error: String?
    /// Set right after `create()` when suggestions were found for the new
    /// project; presented as a sheet. Creation itself never waits on this —
    /// when `AttachmentSuggestions.build` returns nothing (the normal case
    /// with no roots granted) nothing changes here at all.
    @State private var suggestionState: SuggestionSheetState?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    surface = .today
                } label: {
                    Label(QuestSurface.today.title, systemImage: QuestSurface.today.icon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(surface == .today ? theme.tokens.accentPrimary : theme.tokens.foreground)

                Spacer()

                Button {
                    showingTrash = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.tokens.foreground)
                .help("Trash")
            }

            HStack {
                Text("Projects")
                    .font(.caption)
                    .foregroundStyle(theme.tokens.foreground.opacity(0.6))
                Spacer()
                Picker("", selection: $filter) {
                    ForEach(ProjectStateFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 90)
            }

            let visibleProjects = filter.apply(to: store.projects)

            List(visibleProjects, selection: $selection) { project in
                Label(project.name, systemImage: project.icon)
                    .tag(project.id)
                    .contextMenu {
                        Button("Settings…") { settingsProject = project.id }
                        Divider()
                        Button("Active") { setState(project.id, .active) }
                        Button("Pause") { setState(project.id, .paused) }
                        Button("Archive") { setState(project.id, .archived) }
                        Divider()
                        Button("Move to Trash", role: .destructive) { trash(project.id) }
                    }
            }
            .scrollContentBackground(.hidden)
            // Both handlers must test against the NEW value. `visibleProjects`
            // above was computed during the PREVIOUS body pass, so closing over
            // it tested the pre-change list and left, say, a paused project
            // selected and rendered in the detail pane after All → Active.
            .onChange(of: filter) { _, newFilter in
                clearSelectionIfHidden(from: newFilter.apply(to: store.projects))
            }
            .onChange(of: store.projects) { _, newProjects in
                clearSelectionIfHidden(from: filter.apply(to: newProjects))
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(theme.statusColors.danger)
            }

            if selection != nil {
                Picker("", selection: $surface) {
                    ForEach(QuestSurface.allCases.filter(\.requiresProject)) { surface in
                        Label(surface.title, systemImage: surface.icon).tag(surface)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            HStack {
                TextField("New project", text: $newProjectName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(create)
                Button(action: create) { Image(systemName: "plus") }
                    .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(10)
        .background(theme.tokens.surface)
        .sheet(item: $suggestionState) { state in
            AttachmentPicker(store: store, projectID: state.projectID,
                             suggestions: state.suggestions,
                             theme: theme) { suggestionState = nil }
        }
    }

    private func create() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let project = store.createProject(name: name, kind: .software, actor: .user)
        newProjectName = ""
        error = nil
        selection = project.id
        surface = .overview

        // Suggestions never block creation: they are resolved AFTER the
        // project already exists and selection has already moved. With no
        // root granted — the normal case — `build` returns empty and nothing
        // further happens.
        // Each granted root is scanned inside its own balanced access scope
        // (`FolderBookmark.withAccess`); no scoped resource survives this call.
        let suggestions = AttachmentSuggestions.build(projectName: name, in: documents)
        if !suggestions.isEmpty {
            suggestionState = SuggestionSheetState(projectID: project.id, suggestions: suggestions)
        }
    }

    private func setState(_ id: UUID, _ state: ProjectState) {
        do {
            try store.setState(id, state: state, actor: .user)
            // Cleared on success, matching LinkEditor/LinkListView — otherwise
            // one failure leaves a red line under the sidebar forever.
            error = nil
        } catch let failure as QuestError {
            error = failure.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func trash(_ id: UUID) {
        do {
            try store.deleteProject(id, actor: .user)
            if selection == id { selection = nil }
            error = nil
        } catch let failure as QuestError {
            error = failure.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// If the selected project falls outside the current filter — because the
    /// filter changed or the project's state moved it out — the detail
    /// surfaces must not keep showing a project the sidebar no longer lists.
    private func clearSelectionIfHidden(from visibleProjects: [ProjectSummary]) {
        if let selection, !visibleProjects.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }
}
