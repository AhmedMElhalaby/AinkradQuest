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

struct ProjectSidebar: View {
    @Bindable var store: ProjectStore
    let theme: HostTheme
    @Binding var selection: UUID?
    @Binding var surface: QuestSurface
    @Binding var showingTrash: Bool
    @Binding var settingsProject: UUID?

    @State private var newProjectName = ""
    @State private var filter: ProjectStateFilter = .active
    @State private var error: String?

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
            .onChange(of: filter) { clearSelectionIfHidden(from: visibleProjects) }
            .onChange(of: store.projects) { clearSelectionIfHidden(from: visibleProjects) }

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
    }

    private func create() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let project = store.createProject(name: name, kind: .software, actor: .user)
        newProjectName = ""
        selection = project.id
        surface = .overview
    }

    private func setState(_ id: UUID, _ state: ProjectState) {
        do {
            try store.setState(id, state: state, actor: .user)
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
