import SwiftUI
import AinkradAppKit

/// Quest's root — deliberately a thin wrapper whose only job is to mount the
/// toast host ABOVE the view that reads it.
///
/// `.ainkradToastHost()` owns its `AinkradToastCenter` in `@State` and
/// re-injects it into its `content`'s subtree only. Applying it to the same
/// view that reads `\.ainkradToastCenter` resolves that read *above* the
/// modifier, handing back the `@Entry` default — an instance the host's
/// overlay never renders, so every `report(...)` would be silently dropped.
/// `QuestShellContent` therefore lives inside the host, not around it.
public struct QuestShell: View {
    let store: ProjectStore
    let theme: HostTheme
    let documents: PluginDocumentStore

    public init(store: ProjectStore, theme: HostTheme, documents: PluginDocumentStore) {
        self.store = store
        self.theme = theme
        self.documents = documents
    }

    public var body: some View {
        QuestShellContent(store: store, theme: theme, documents: documents)
            .ainkradToastHost()
    }
}

/// The shell proper. Owns selection state, routes sheets, and owns the single
/// `report` path that will replace the per-view `@State var error: String?`
/// scattered across four surfaces as those surfaces migrate (Tasks 8–13).
///
/// The surfaces below are still called with their pre-migration initializers
/// (`theme:`, no `report:`) on purpose: each later task flips one surface and
/// its call site here in the same commit, so every task stays independently
/// buildable.
struct QuestShellContent: View {
    @Bindable var store: ProjectStore
    let theme: HostTheme
    let documents: PluginDocumentStore

    @State private var surface: QuestSurface = .landing
    @State private var selectedProject: UUID?
    @State private var showingTrash = false
    @State private var showingCommands = false
    @State private var settingsProject: UUID?
    @State private var showingNewProject = false
    /// Owned by the shell, not by `NewProjectForm`, so it outlives the form the
    /// suggestions were resolved in. See the sibling modal below.
    @State private var suggestionState: SuggestionSheetState?
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    /// Resolves to the center that `.ainkradToastHost()` on `QuestShell`
    /// injected, because this view is that modifier's content.
    @Environment(\.ainkradToastCenter) private var toasts

    private var hasProject: Bool { selectedProject != nil }

    private var projectName: String? {
        selectedProject.flatMap { id in store.projects.first { $0.id == id }?.name }
    }

    var body: some View {
        VStack(spacing: 0) {
            QuestHeader(trail: BreadcrumbTrail.items(projectName: projectName,
                                                     surface: surface, sheet: nil),
                        surface: $surface,
                        searchText: $searchText,
                        searchFocused: $searchFocused,
                        showsSwitcher: SurfaceVisibility.showsSwitcher(hasProject: hasProject),
                        onNew: { newItemOrProject() },
                        onSettings: { settingsProject = selectedProject },
                        onTrash: { showingTrash = true })

            // A failed persist is a standing condition, not an event, so it is
            // a banner rather than a toast — a toast would expire while the
            // write was still lost.
            if let message = store.persistenceFailure {
                AinkradBanner(message: message, status: .danger)
                    .padding(.horizontal, AinkradSpacing.md)
                    .padding(.top, AinkradSpacing.sm)
            }

            HStack(spacing: 0) {
                QuestSidebar(store: store, documents: documents,
                             selection: $selectedProject, surface: $surface,
                             showingTrash: $showingTrash,
                             settingsProject: $settingsProject,
                             report: { report($0, status: $1) })
                    .frame(width: 232)
                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ainkradPanel()
        // Selection and surface must stay reachable together: clearing the
        // project while on Board previously left the pane rendering nothing.
        .onChange(of: selectedProject) { _, _ in
            withAnimation(AinkradMotion.present) {
                surface = SurfaceVisibility.resolved(surface: surface, hasProject: hasProject)
            }
        }
        // The single new-project presentation. Every entry point — the
        // sidebar button (via `\.questNewProject`), the command menu's
        // `.newProject`, the ⌘N chord and the header's "+" with no project
        // selected — flips this one flag, so none of them can drift.
        .environment(\.questNewProject, QuestNewProjectAction { showingNewProject = true })
        .ainkradModal(isPresented: $showingNewProject) {
            NewProjectForm(store: store, documents: documents,
                           report: { report($0, status: $1) }) { created, suggestions in
                showingNewProject = false
                selectedProject = created
                surface = .overview
                // Only after selection has moved, and only when there is
                // something to offer — the normal (no granted root) case leaves
                // this nil and shows no picker.
                if !suggestions.isEmpty {
                    suggestionState = SuggestionSheetState(projectID: created,
                                                           suggestions: suggestions)
                }
            }
        }
        // A SIBLING of the new-project modal, not nested inside it: dismissing
        // `showingNewProject` tears `NewProjectForm`'s subtree out of the
        // overlay, so a picker presented from within the form could never
        // render. The shell outlives the form, so this presenter is still
        // mounted when `suggestionState` is set — one statement earlier, above.
        .ainkradModal(isPresented: Binding(get: { suggestionState != nil },
                                           set: { if !$0 { suggestionState = nil } })) {
            if let state = suggestionState {
                AttachmentPicker(store: store, projectID: state.projectID,
                                 suggestions: state.suggestions) { suggestionState = nil }
            }
        }
        .ainkradModal(isPresented: $showingCommands) {
            QuestCommandMenu(store: store, hasProject: hasProject,
                             statuses: currentStatuses) { perform($0) }
        }
        // Trash and project settings keep their existing `.sheet` presentation
        // until their own migration tasks move them to `.ainkradModal`.
        .sheet(isPresented: $showingTrash) {
            TrashView(store: store, theme: theme)
        }
        .sheet(item: Binding(
            get: { settingsProject.flatMap { store.openProject($0)?.project } },
            set: { settingsProject = $0?.id })) { project in
            ProjectSettingsSheet(store: store, project: project, theme: theme)
        }
        .background(shortcuts)
    }

    @ViewBuilder private var content: some View {
        // Animated by surface so switching materializes rather than jump-cuts.
        ZStack {
            switch surface {
            case .today:
                TodaySurface(store: store, theme: theme, onOpen: open)
            case .overview, .list, .board, .timeline:
                if let id = selectedProject, let document = store.openProject(id) {
                    switch surface {
                    case .overview: OverviewSurface(store: store, document: document,
                                                    theme: theme)
                    case .list: ListSurface(store: store, document: document, theme: theme)
                    case .board: BoardSurface(store: store, document: document, theme: theme)
                    case .timeline: TimelineSurface(document: document, theme: theme)
                    case .today: EmptyView()
                    }
                } else {
                    let reason = EmptyReason.classify(totalCount: 0, visibleCount: 0,
                                                      hasProject: false)
                    AinkradEmptyState(icon: reason.icon, title: reason.title,
                                      message: reason.message)
                }
            }
        }
        .animation(AinkradMotion.present, value: surface)
    }

    private var currentStatuses: [Status] {
        guard let id = selectedProject, let document = store.openProject(id) else { return [] }
        return document.project.statusScheme.statuses
    }

    /// The single reporting path. Surfaces receive this instead of owning an
    /// error string, one surface at a time from Task 8 onward.
    func report(_ message: String, status: AinkradStatus = .danger) {
        toasts.show(message, status: status)
    }

    private func open(_ item: WorkItem) {
        selectedProject = item.projectID
        surface = .list
    }

    private func newItemOrProject() {
        // Item creation belongs to the owning surface; with no project there is
        // nothing to add an item to, so "+" means "new project".
        if hasProject {
            report("Use the item list to add an item.", status: .neutral)
        } else {
            showingNewProject = true
        }
    }

    private func perform(_ action: CommandAction) {
        showingCommands = false
        switch action {
        case .openSurface(let target): surface = target
        case .selectProject(let id): selectedProject = id
        case .openTrash: showingTrash = true
        case .openSettings: settingsProject = selectedProject
        case .newProject:
            showingNewProject = true
        case .newItem, .setStatus:
            // Both need a focused item, which the shell does not track; the
            // owning surface handles them. Reported rather than silently
            // dropped so the gap is visible instead of feeling broken.
            report("Open the item first, then use its editor.", status: .neutral)
        }
    }

    /// Keyboard entry points driven BY the binding table, not duplicating it.
    /// Hardcoding the chords here would leave `KeyBindings.duplicates` guarding
    /// a table nothing reads, and let the chord shown on a button drift from
    /// the chord that actually fires.
    @ViewBuilder private var shortcuts: some View {
        ForEach(KeyBindings.all, id: \.id) { binding in
            Button("") { activate(binding.id) }
                .keyboardShortcut(KeyEquivalent(binding.key),
                                  modifiers: binding.modifiers.eventModifiers)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func activate(_ id: String) {
        switch id {
        case "commandMenu": showingCommands.toggle()
        case "newProject": perform(.newProject)
        case "focusSearch": searchFocused = true
        case "newItem": perform(.newItem)
        default:
            // A binding added to `KeyBindings.all` with no handler here fires a
            // real chord and does nothing, which is indistinguishable from a
            // broken app. Trap it in debug and surface it at runtime rather
            // than letting it be inert.
            assertionFailure("KeyBindings.all has binding '\(id)' with no handler in QuestShellContent.activate")
            report("That shortcut is not wired up yet.", status: .warning)
        }
    }
}
