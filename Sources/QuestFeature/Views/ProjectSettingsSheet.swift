import SwiftUI
import AinkradAppKit

/// The theme lookup for `ProjectColorToken` (declared in `Models/`, so the MCP
/// layer can validate against the same closed set without importing a view).
///
/// It takes the DERIVED token structs rather than the `HostTheme` object,
/// because those are what the host actually injects into the SwiftUI
/// environment (`\.ainkradTheme`, `\.ainkradStatusColors`). Taking `HostTheme`
/// forced every view that wanted a swatch to have the class threaded down to
/// it by hand.
extension ProjectColorToken {
    func color(tokens: HostThemeTokens, statusColors: AinkradStatusColors) -> Color {
        switch self {
        case .accentPrimary: tokens.accentPrimary
        case .accentSecondary: tokens.accentSecondary
        case .success: statusColors.success
        case .warning: statusColors.warning
        case .danger: statusColors.danger
        case .muted: tokens.foreground.opacity(0.4)
        }
    }
}

/// Validation for the settings sheet, pure so it can be tested without a view.
enum ProjectSettingsValidation {
    /// Mirrors `LinkValidation.Outcome`: either the normalized value or the
    /// message to put in front of the user.
    enum NameOutcome: Equatable {
        case valid(String)
        case invalid(String)

        var value: String? { if case .valid(let name) = self { name } else { nil } }
    }

    /// The same rule `ProjectSidebar.create()` enforces on the creation path.
    /// It was enforced there and nowhere else, so a rename could empty a name
    /// that could not have been created empty, producing a nameless sidebar row.
    static func validate(name: String) -> NameOutcome {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalid("A project needs a name.") }
        return .valid(trimmed)
    }
}

/// Name, summary, icon and colour. Draft-until-Save, like ItemEditor.
///
/// Presented through `.ainkradModal`, which is an OVERLAY modifier and injects
/// no `DismissAction` — so this view must never reach for
/// `@Environment(\.dismiss)`. Closing is the presenter's job, requested through
/// `onClose`; a `dismiss()` here would compile and do nothing.
struct ProjectSettingsSheet: View {
    @Bindable var store: ProjectStore
    let report: (String, AinkradStatus) -> Void
    /// Asks the presenter to take this sheet down. Called ONLY as the last
    /// statement of a path, because it unmounts this subtree — a `@State`
    /// write after it would land in a view that no longer exists.
    let onClose: () -> Void

    @State private var draft: Project
    @State private var colorToken: ProjectColorToken
    /// The scheme editor's confirm step, hoisted here so this sheet can see it.
    /// `StatusSchemeEditor` remains its only writer; this sheet only READS it,
    /// to refuse to save while a plan is awaiting confirmation.
    @State private var pendingSchemePlan: SchemePlan.Plan?

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var statusColors

    init(store: ProjectStore, project: Project,
         report: @escaping (String, AinkradStatus) -> Void,
         onClose: @escaping () -> Void) {
        self.store = store
        self.report = report
        self.onClose = onClose
        _draft = State(initialValue: project)
        _colorToken = State(initialValue: ProjectColorToken.resolve(project.colorToken))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Project settings", subtitle: draft.name)

            // `.ainkradModal` is an overlay scoped to the presenter's bounds
            // with NO intrinsic scrolling — unlike the `.sheet` it replaced,
            // which sized its own window. Header + fields + the scheme editor
            // (a 180pt list, an add row, one row per occupied removal, and the
            // confirm block) can easily exceed the shell's height, and without
            // this cap the button row below would be pushed out of reach with
            // no way to scroll back to it.
            ScrollView {
                VStack(alignment: .leading, spacing: AinkradSpacing.md) {
                    fields
                    StatusSchemeEditor(store: store, project: draft, report: report,
                                       pendingPlan: $pendingSchemePlan)
                }
                .padding(.trailing, AinkradSpacing.xs)
            }
            // A deliberate cap, matching `ItemEditor`'s, so the buttons below
            // always stay on screen.
            .frame(maxHeight: 420)

            HStack {
                AinkradButton(title: "Cancel", style: .secondary, action: onClose)
                Spacer()
                AinkradButton(title: "Save", style: .primary, action: save)
            }
        }
        // A deliberate fixed sheet width, so the form does not reflow with the
        // pane behind it. Inside `.ainkradModal`'s 480pt cap.
        .frame(width: 420)
        .foregroundStyle(theme.foreground)
        .onSubmit(save)
        // Mounted only while NO scheme plan is pending; `StatusSchemeEditor`
        // mounts its own default-action Apply while one IS. Exactly one
        // default action exists at any moment, so Return is never ambiguous.
        .background(pendingSchemePlan == nil ? defaultActionSave : nil)
    }

    /// Return-with-nothing-focused commits, exactly as the pre-kit
    /// `Button("Save").keyboardShortcut(.defaultAction)` did.
    @ViewBuilder private var defaultActionSave: some View {
        Button("") { save() }
            .keyboardShortcut(.defaultAction)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var fields: some View {
        AinkradFormRow(title: "Name") {
            AinkradTextField(text: $draft.name, placeholder: "Name")
        }
        AinkradFormRow(title: "Summary") {
            AinkradTextField(text: $draft.summaryText, placeholder: "Summary")
        }
        AinkradFormRow(title: "Icon", help: "An SF Symbol name") {
            AinkradTextField(text: $draft.icon, placeholder: "SF Symbol")
        }
        AinkradFormRow(title: "Colour") {
            AinkradSelect(items: ProjectColorToken.allCases, selection: $colorToken,
                          label: { $0.title },
                          swatch: { $0.color(tokens: theme, statusColors: statusColors) })
        }
        // The kind picker only relabels the project; it does NOT change an
        // existing project's status scheme. Schemes ARE editable now, via
        // the `StatusSchemeEditor` below — this picker still does not
        // retroactively switch one.
        AinkradFormRow(title: "Kind") {
            AinkradSegmentedPicker(items: [ProjectKind.software, .general],
                                   selection: $draft.kind) { $0.settingsTitle }
        }
    }

    private func save() {
        // A pending scheme plan is a confirm step the user is looking at.
        // Saving now would close the sheet and abandon it, so Return (or the
        // Save button) refuses instead of silently discarding the plan.
        guard pendingSchemePlan == nil else {
            report("Apply or cancel the status changes first.", .warning)
            return
        }
        var draft = draft
        switch ProjectSettingsValidation.validate(name: draft.name) {
        case .invalid(let message):
            report(message, .danger)
            return
        case .valid(let name):
            draft.name = name
        }
        draft.colorToken = colorToken.rawValue
        // StatusSchemeEditor above applies scheme changes directly through the
        // store on "Apply", immediately — unlike the rest of this sheet, which
        // is draft-until-Save. `draft.statusScheme` is stale from init time, so
        // pull the store's current copy right before saving, exactly as
        // ItemEditor.save() does for links: otherwise this write would silently
        // revert a scheme change the user already applied and confirmed.
        if let current = store.openProject(draft.id)?.project.statusScheme {
            draft.statusScheme = current
        }
        do {
            try store.updateProject(draft, actor: .user)
            // LAST statement on this path — everything after it would run in an
            // unmounted subtree.
            onClose()
        } catch let failure as QuestError {
            report(failure.message, .danger)
        } catch {
            report(error.localizedDescription, .danger)
        }
    }
}

private extension ProjectKind {
    /// The label the settings picker shows. Local to this file because it is a
    /// UI string, not part of the persisted vocabulary.
    var settingsTitle: String {
        switch self {
        case .software: "Software"
        case .general: "General"
        }
    }
}
