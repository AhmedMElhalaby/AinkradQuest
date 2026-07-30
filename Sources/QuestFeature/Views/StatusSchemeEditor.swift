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

/// Pure decision logic for `StatusSchemeEditor`, extracted so the "read the
/// scheme fresh, not a stale capture" behavior is a parameter a test controls
/// directly, independent of SwiftUI/View lifecycle.
enum SchemeEditorState {
    /// Plans a proposed set of drafts against an explicitly-passed `current`
    /// scheme. Forwards straight to `SchemePlan.plan`; the only reason this
    /// exists is to make `current` a parameter instead of something read off
    /// `self.project` inside a View.
    static func plan(current: StatusScheme, drafts: [StatusDraft],
                     reassignments: [String: String], items: [WorkItem]) -> SchemePlan.Outcome {
        SchemePlan.plan(current: current, proposed: StatusDraft.scheme(from: drafts),
                        reassignments: reassignments, items: items)
    }

    /// Given a just-applied plan, the next drafts (re-seeded from
    /// `plan.proposed`) and cleared reassignments.
    static func afterApply(_ plan: SchemePlan.Plan) -> (drafts: [StatusDraft],
                                                         reassignments: [String: String]) {
        (StatusDraft.drafts(from: plan.proposed), [:])
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
            // While a plan is pending, the visible rows must stay in lockstep
            // with what the user confirmed — otherwise a post-review edit to
            // an already-reviewed row is silently discarded when Apply
            // re-seeds `drafts` from `plan.proposed`. Disabling every editable
            // control keeps Cancel/Apply as the only possible actions.
            .disabled(pendingPlan != nil)

            HStack {
                TextField("New status", text: $newName)
                    .disabled(pendingPlan != nil)
                Button("Add") {
                    drafts.append(StatusDraft.make(name: newName, existing: drafts))
                    newName = ""
                }
                .disabled(pendingPlan != nil || newName.trimmingCharacters(in: .whitespaces).isEmpty)
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
            .disabled(pendingPlan != nil)

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

    /// The scheme as it stands in the store RIGHT NOW, not the copy captured
    /// when this sheet opened. Within one sheet session, Apply can run more
    /// than once — a second plan must diff against what the first apply just
    /// wrote, or a revert of that first change is invisible (diffed against
    /// the pre-session original, it looks like a no-op) and a re-removal of
    /// an already-removed status gets proposed again. Falls back to the
    /// captured `project` only if the store somehow has nothing open (should
    /// not happen for an existing project mid-session).
    private var currentScheme: StatusScheme {
        store.openProject(project.id)?.project.statusScheme ?? project.statusScheme
    }

    private var occupiedRemovals: [Status] {
        let surviving = Set(drafts.map(\.id))
        return currentScheme.statuses
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
        switch SchemeEditorState.plan(current: currentScheme, drafts: drafts,
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
            // Re-seed from what was actually just applied, and drop any
            // leftover pre-apply edit state, so a second Apply in this same
            // sheet session diffs against reality instead of stale rows.
            let next = SchemeEditorState.afterApply(plan)
            drafts = next.drafts
            reassignments = next.reassignments
            pendingPlan = nil
            error = nil
        } catch let failure as QuestError {
            error = failure.message
        } catch {
            self.error = error.localizedDescription
        }
    }
}
