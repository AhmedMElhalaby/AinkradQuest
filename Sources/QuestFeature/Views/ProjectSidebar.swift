import SwiftUI
import AinkradAppKit

struct ProjectSidebar: View {
    @Bindable var store: ProjectStore
    let theme: HostTheme
    @Binding var selection: UUID?
    @Binding var surface: QuestSurface

    @State private var newProjectName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                surface = .today
            } label: {
                Label(QuestSurface.today.title, systemImage: QuestSurface.today.icon)
            }
            .buttonStyle(.plain)
            .foregroundStyle(surface == .today ? theme.tokens.accentPrimary : theme.tokens.foreground)

            Text("Projects")
                .font(.caption)
                .foregroundStyle(theme.tokens.foreground.opacity(0.6))

            List(store.activeProjects, selection: $selection) { project in
                Label(project.name, systemImage: project.icon)
                    .tag(project.id)
            }
            .scrollContentBackground(.hidden)

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
}
