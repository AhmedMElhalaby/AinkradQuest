import SwiftUI
import AinkradAppKit

/// The colour choices a project may carry.
///
/// THEME TOKEN NAMES, never raw colours: the host owns the palette, so a
/// project that stored `#FF0000` would be unreadable in one of the themes and
/// would not follow a theme change. The set is closed because `colorToken` is a
/// free-form `String` on `Project` — an unresolvable name would render as
/// nothing, so the control offers only names the theme is known to define.
enum ProjectColorToken: String, CaseIterable, Identifiable {
    case accentPrimary, accentSecondary, success, warning, danger, muted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accentPrimary: "Accent"
        case .accentSecondary: "Secondary"
        case .success: "Green"
        case .warning: "Amber"
        case .danger: "Red"
        case .muted: "Grey"
        }
    }

    /// Maps whatever a project currently stores onto the closed set. Projects
    /// created before this control existed hold the default `"accent"`, and a
    /// document could carry anything; both land on `.accentPrimary` rather than
    /// leaving the picker with no selection.
    static func resolve(_ token: String) -> ProjectColorToken {
        ProjectColorToken(rawValue: token) ?? .accentPrimary
    }

    @MainActor func color(in theme: HostTheme) -> Color {
        switch self {
        case .accentPrimary: theme.tokens.accentPrimary
        case .accentSecondary: theme.tokens.accentSecondary
        case .success: theme.statusColors.success
        case .warning: theme.statusColors.warning
        case .danger: theme.statusColors.danger
        case .muted: theme.tokens.foreground.opacity(0.4)
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
struct ProjectSettingsSheet: View {
    @Bindable var store: ProjectStore
    let theme: HostTheme

    @State private var draft: Project
    @State private var colorToken: ProjectColorToken
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(store: ProjectStore, project: Project, theme: HostTheme) {
        self.store = store
        self.theme = theme
        _draft = State(initialValue: project)
        _colorToken = State(initialValue: ProjectColorToken.resolve(project.colorToken))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Name", text: $draft.name)
            TextField("Summary", text: $draft.summaryText)
            TextField("SF Symbol", text: $draft.icon)
            Picker("Colour", selection: $colorToken) {
                ForEach(ProjectColorToken.allCases) { token in
                    Label {
                        Text(token.title)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(token.color(in: theme))
                    }
                    .tag(token)
                }
            }
            // The kind picker only relabels the project; it does NOT change an
            // existing project's status scheme. Schemes ARE editable now, via
            // the `StatusSchemeEditor` below — this picker still does not
            // retroactively switch one.
            Picker("Kind", selection: $draft.kind) {
                Text("Software").tag(ProjectKind.software)
                Text("General").tag(ProjectKind.general)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(theme.statusColors.danger)
            }

            Divider().overlay(theme.tokens.surface)
            StatusSchemeEditor(store: store, project: draft, theme: theme)

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
        var draft = draft
        switch ProjectSettingsValidation.validate(name: draft.name) {
        case .invalid(let message):
            error = message
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
            dismiss()
        } catch let failure as QuestError {
            error = failure.message
        } catch {
            self.error = error.localizedDescription
        }
    }
}
