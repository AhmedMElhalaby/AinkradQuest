import SwiftUI
import AinkradAppKit

/// One editable row. Separate from `Status` because a row in flight may be
/// half-typed, and because a NEW row needs an id minted from its name while an
/// EXISTING row must keep the id items already store.
struct StatusDraft: Identifiable, Equatable {
    let id: String
    var name: String
    var category: StatusCategory
    var color: ProjectColorToken

    static func drafts(from scheme: StatusScheme) -> [StatusDraft] {
        scheme.statuses.map {
            StatusDraft(id: $0.id, name: $0.name, category: $0.category,
                        color: ProjectColorToken.resolve($0.colorToken))
        }
    }

    static func scheme(from drafts: [StatusDraft]) -> StatusScheme {
        StatusScheme(statuses: drafts.map {
            Status(id: $0.id, name: $0.name, category: $0.category,
                   colorToken: $0.color.rawValue)
        })
    }

    /// Mints a stable id from a name, unique among `existing`. Ids are permanent
    /// once items reference them, so this runs only when a row is created.
    static func make(name: String, existing: [StatusDraft]) -> StatusDraft {
        let base = name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        let seed = base.isEmpty ? "status" : base
        var candidate = seed
        var suffix = 2
        while existing.contains(where: { $0.id == candidate }) {
            candidate = "\(seed)_\(suffix)"
            suffix += 1
        }
        return StatusDraft(id: candidate, name: name.isEmpty ? "New status" : name,
                           category: .todo, color: .accentPrimary)
    }
}

/// Status-scheme editor hosted inside `ProjectSettingsSheet`. Unlike the rest
/// of that sheet, this applies through the store IMMEDIATELY on "Apply" — it
/// plans first via `SchemePlan.plan`, shows the plan's own `summary`, and
/// applies that SAME plan value, so the preview the user confirms can never
/// drift from what actually executes.
struct StatusSchemeEditor: View {
    @Bindable var store: ProjectStore
    let project: Project
    let theme: HostTheme

    @State private var drafts: [StatusDraft]
    @State private var newName = ""
    @State private var reassignments: [String: String] = [:]
    @State private var error: String?
    @State private var pendingPlan: SchemePlan.Plan?

    init(store: ProjectStore, project: Project, theme: HostTheme) {
        self.store = store
        self.project = project
        self.theme = theme
        _drafts = State(initialValue: StatusDraft.drafts(from: project.statusScheme))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Statuses").font(.headline).foregroundStyle(theme.tokens.accentPrimary)

            List {
                ForEach($drafts) { $draft in
                    HStack {
                        TextField("Name", text: $draft.name)
                        Picker("", selection: $draft.category) {
                            ForEach(StatusCategory.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        .labelsHidden().frame(width: 110)
                        Picker("", selection: $draft.color) {
                            ForEach(ProjectColorToken.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden().frame(width: 110)
                        Button {
                            drafts.removeAll { $0.id == draft.id }
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain)
                    }
                }
                .onMove { drafts.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(height: 180)
            .scrollContentBackground(.hidden)

            HStack {
                TextField("New status", text: $newName)
                Button("Add") {
                    drafts.append(StatusDraft.make(name: newName, existing: drafts))
                    newName = ""
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Any removed status that still holds items needs a destination
            // before the plan will validate.
            ForEach(occupiedRemovals, id: \.id) { status in
                HStack {
                    Text("Move \(status.name)'s \(itemCount(status.id)) item(s) to")
                        .font(.caption)
                    Picker("", selection: binding(for: status.id)) {
                        Text("Choose…").tag("")
                        ForEach(drafts) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                }
            }

            if let error {
                Text(error).font(.caption).foregroundStyle(theme.statusColors.danger)
            }

            if let pendingPlan {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This will: \(pendingPlan.summary)").font(.caption)
                    HStack {
                        Button("Cancel") { self.pendingPlan = nil }
                        Button("Apply") { apply(pendingPlan) }
                            .keyboardShortcut(.defaultAction)
                    }
                }
            } else {
                Button("Review changes", action: review)
            }
        }
        .textFieldStyle(.roundedBorder)
        .foregroundStyle(theme.tokens.foreground)
    }

    private var items: [WorkItem] { store.allItems(in: project.id) }

    private var occupiedRemovals: [Status] {
        let surviving = Set(drafts.map(\.id))
        return project.statusScheme.statuses
            .filter { !surviving.contains($0.id) && itemCount($0.id) > 0 }
    }

    private func itemCount(_ statusID: String) -> Int {
        items.filter { $0.statusID == statusID }.count
    }

    private func binding(for statusID: String) -> Binding<String> {
        Binding(get: { reassignments[statusID] ?? "" },
                set: { reassignments[statusID] = $0.isEmpty ? nil : $0 })
    }

    /// Plans first and shows the result. The user confirms the SAME plan value
    /// that will execute, so the preview cannot disagree with the outcome.
    private func review() {
        switch SchemePlan.plan(current: project.statusScheme,
                               proposed: StatusDraft.scheme(from: drafts),
                               reassignments: reassignments, items: items) {
        case .invalid(let message):
            error = message
            pendingPlan = nil
        case .valid(let plan):
            error = nil
            pendingPlan = plan
        }
    }

    private func apply(_ plan: SchemePlan.Plan) {
        do {
            try store.applyScheme(plan, to: project.id, actor: .user)
            pendingPlan = nil
            error = nil
        } catch let failure as QuestError {
            error = failure.message
        } catch {
            self.error = error.localizedDescription
        }
    }
}
