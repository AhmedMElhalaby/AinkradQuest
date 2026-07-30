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

/// Wraps a freshly created project's attachment suggestions for presentation,
/// which needs `Identifiable` rather than a bare tuple. File-scope (no longer
/// private to the sidebar) because `NewProjectForm` owns creation now.
struct SuggestionSheetState: Identifiable {
    let projectID: UUID
    let suggestions: [AttachmentSuggestion]
    var id: UUID { projectID }
}

extension EnvironmentValues {
    /// Opens the shell's single new-project modal. The sidebar's "New project"
    /// button, the command menu's `.newProject`, the ⌘N chord and the header's
    /// "+" (with no project selected) all have to reach ONE presentation, and
    /// `QuestSidebar.init` is a fixed contract with no room for another
    /// binding — so the shell publishes the trigger instead.
    @Entry var questNewProject: () -> Void = {}
}

struct QuestSidebar: View {
    @Bindable var store: ProjectStore
    let documents: PluginDocumentStore
    @Binding var selection: UUID?
    @Binding var surface: QuestSurface
    @Binding var showingTrash: Bool
    @Binding var settingsProject: UUID?
    let report: (String, AinkradStatus) -> Void

    @State private var filter: ProjectStateFilter = .active
    @Environment(\.questNewProject) private var newProject

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            // Today stays in the sidebar: it is the cross-project entry point,
            // not a surface of the selected project, so the header's switcher
            // (which is project-scoped) is the wrong home for it.
            AinkradListRow(isSelected: surface == .today,
                           onTap: { surface = .today; selection = nil },
                           leading: { AinkradIconGlyph(systemName: QuestSurface.today.icon) },
                           title: QuestSurface.today.title,
                           trailing: { EmptyView() })

            HStack {
                AinkradSectionHeader(title: "Projects")
                Spacer()
                AinkradSelect(items: ProjectStateFilter.allCases, selection: $filter) { $0.title }
                    .frame(maxWidth: 104)
            }

            ScrollView {
                VStack(spacing: AinkradSpacing.xs) {
                    ForEach(visibleProjects) { project in
                        AinkradListRow(isSelected: selection == project.id,
                                       onTap: { selection = project.id },
                                       leading: { AinkradIconGlyph(systemName: project.icon) },
                                       title: project.name,
                                       trailing: { EmptyView() })
                            .ainkradContextMenu(menu(for: project))
                    }
                }
            }
            // Both handlers must test against the NEW value. `visibleProjects`
            // is computed from the PREVIOUS body pass's state, so closing over
            // it tested the pre-change list and left, say, a paused project
            // selected and rendered in the detail pane after All → Active.
            .onChange(of: filter) { _, newFilter in
                clearSelectionIfHidden(from: newFilter.apply(to: store.projects))
            }
            .onChange(of: store.projects) { _, newProjects in
                clearSelectionIfHidden(from: filter.apply(to: newProjects))
            }

            Spacer(minLength: 0)

            AinkradButton(title: "New project", style: .secondary, icon: "plus") {
                newProject()
            }
        }
        .padding(AinkradSpacing.md)
    }

    private var visibleProjects: [ProjectSummary] { filter.apply(to: store.projects) }

    private func menu(for project: ProjectSummary) -> [AinkradMenuItem] {
        [
            AinkradMenuItem(title: "Settings…", systemName: "gearshape") {
                settingsProject = project.id
            },
            AinkradMenuItem(title: "Active", systemName: "play.circle") {
                setState(project.id, .active)
            },
            AinkradMenuItem(title: "Pause", systemName: "pause.circle") {
                setState(project.id, .paused)
            },
            AinkradMenuItem(title: "Archive", systemName: "archivebox") {
                setState(project.id, .archived)
            },
            AinkradMenuItem(title: "Move to Trash", systemName: "trash", isDestructive: true) {
                trash(project.id)
            },
        ]
    }

    private func setState(_ id: UUID, _ state: ProjectState) {
        do {
            try store.setState(id, state: state, actor: .user)
            report("Moved to \(state.rawValue)", .success)
        } catch let failure as QuestError {
            report(failure.message, .danger)
        } catch {
            report(error.localizedDescription, .danger)
        }
    }

    private func trash(_ id: UUID) {
        do {
            try store.deleteProject(id, actor: .user)
            if selection == id { selection = nil }
            report("Moved to Trash", .success)
        } catch let failure as QuestError {
            report(failure.message, .danger)
        } catch {
            report(error.localizedDescription, .danger)
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

/// Project creation, moved out of the sidebar footer into a modal so the
/// sidebar is a list and nothing else.
struct NewProjectForm: View {
    @Bindable var store: ProjectStore
    let documents: PluginDocumentStore
    let report: (String, AinkradStatus) -> Void
    let onCreated: (UUID) -> Void

    @State private var name = ""
    @State private var suggestionState: SuggestionSheetState?

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "New project")
            AinkradFormRow(title: "Name") {
                AinkradTextField(text: $name, placeholder: "Project name")
            }
            HStack {
                Spacer()
                AinkradButton(title: "Create", style: .primary) { create() }
            }
        }
        .padding(AinkradSpacing.lg)
        .frame(width: 420)
        .ainkradModal(isPresented: Binding(get: { suggestionState != nil },
                                           set: { if !$0 { suggestionState = nil } })) {
            if let state = suggestionState {
                AttachmentPicker(store: store, projectID: state.projectID,
                                 suggestions: state.suggestions) { suggestionState = nil }
            }
        }
    }

    private func create() {
        guard !trimmed.isEmpty else { return }
        let name = trimmed
        let project = store.createProject(name: name, kind: .software, actor: .user)
        self.name = ""
        onCreated(project.id)
        report("Created \(project.name)", .success)

        // Suggestions never block creation: resolved AFTER the project exists
        // and selection has moved. With no root granted — the normal case —
        // `build` returns empty and nothing further happens. Each root is
        // scanned inside its own balanced `FolderBookmark.withAccess` scope;
        // no scoped resource survives this call.
        let suggestions = AttachmentSuggestions.build(projectName: name, in: documents)
        if !suggestions.isEmpty {
            suggestionState = SuggestionSheetState(projectID: project.id,
                                                  suggestions: suggestions)
        }
    }
}
