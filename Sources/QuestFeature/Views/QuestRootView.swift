import SwiftUI
import AinkradAppKit

public enum QuestSurface: String, CaseIterable, Identifiable, Sendable {
    case today, overview, list, board, timeline

    public var id: String { rawValue }
    public static let landing = QuestSurface.today

    public var title: String {
        switch self {
        case .today: "Today"
        case .overview: "Overview"
        case .list: "List"
        case .board: "Board"
        case .timeline: "Timeline"
        }
    }

    public var icon: String {
        switch self {
        case .today: "tray.full"
        case .overview: "square.text.square"
        case .list: "list.bullet.indent"
        case .board: "rectangle.split.3x1"
        case .timeline: "calendar.day.timeline.left"
        }
    }

    /// Today is cross-project; everything else reads one project's document.
    public var requiresProject: Bool { self != .today }
}

public struct QuestRootView: View {
    @Bindable var store: ProjectStore
    let theme: HostTheme

    @State private var surface: QuestSurface = .landing
    @State private var selectedProject: UUID?
    @State private var showingTrash = false
    @State private var settingsProject: UUID?

    public init(store: ProjectStore, theme: HostTheme) {
        self.store = store
        self.theme = theme
    }

    public var body: some View {
        HStack(spacing: 0) {
            ProjectSidebar(store: store, theme: theme,
                           selection: $selectedProject, surface: $surface,
                           showingTrash: $showingTrash, settingsProject: $settingsProject)
                .frame(width: 220)
            Divider().overlay(theme.tokens.surface)
            VStack(spacing: 0) {
                if let message = store.persistenceFailure {
                    banner(message)
                }
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.tokens.background)
        .sheet(isPresented: $showingTrash) {
            TrashView(store: store, theme: theme)
        }
        .sheet(item: Binding(
            get: { settingsProject.flatMap { store.openProject($0)?.project } },
            set: { settingsProject = $0?.id })) { project in
            ProjectSettingsSheet(store: store, project: project, theme: theme)
        }
    }

    @ViewBuilder private var content: some View {
        switch surface {
        case .today:
            TodaySurface(store: store, theme: theme, onOpen: open)
        default:
            if let projectID = selectedProject, let document = store.openProject(projectID) {
                switch surface {
                case .overview: OverviewSurface(store: store, document: document, theme: theme)
                case .list: ListSurface(store: store, document: document, theme: theme)
                case .board: BoardSurface(store: store, document: document, theme: theme)
                case .timeline: TimelineSurface(document: document, theme: theme)
                case .today: EmptyView()
                }
            } else {
                ContentUnavailableView("No project selected", systemImage: "folder")
                    .foregroundStyle(theme.tokens.foreground)
            }
        }
    }

    /// Jump from a cross-project row into the project that owns it.
    private func open(_ item: WorkItem) {
        selectedProject = item.projectID
        surface = .list
    }

    /// A write that could not be persisted is stated, never swallowed.
    private func banner(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(theme.statusColors.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(theme.tokens.surface)
    }
}
