import SwiftUI
import AinkradAppKit

/// The other half of soft delete. Without this view, "restorable" is a claim
/// with no interface behind it — and the MCP deletes are classified on the
/// promise that a person can undo them.
struct TrashView: View {
    @Bindable var store: ProjectStore
    let theme: HostTheme

    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Text(error).font(.caption).foregroundStyle(theme.statusColors.danger)
            }
            Section("Projects") {
                ForEach(store.trashedProjects) { project in
                    HStack {
                        Text(project.name)
                        Spacer()
                        Button("Restore") { restoreProject(project.id) }
                    }
                }
            }
            Section("Items") {
                ForEach(store.projects) { project in
                    ForEach(store.allItems(in: project.id).filter(\.isDeleted)) { item in
                        HStack {
                            Text("\(project.name): \(item.title)")
                            Spacer()
                            Button("Restore") { restoreItem(item.id) }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(theme.tokens.foreground)
    }

    private func restoreProject(_ id: UUID) {
        do {
            try store.restoreProject(id, actor: .user)
            error = nil
        } catch let failure as QuestError {
            error = failure.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func restoreItem(_ id: UUID) {
        do {
            try store.restoreItem(id, actor: .user)
            error = nil
        } catch let failure as QuestError {
            error = failure.message
        } catch {
            self.error = error.localizedDescription
        }
    }
}
