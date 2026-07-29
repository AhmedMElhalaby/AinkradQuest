import SwiftUI
import AinkradAppKit

/// One-line capture syntax: `bug: title #label #label !!`. Deliberately tiny —
/// anything richer belongs in the editor, and a capture box you have to think
/// about is one you stop using.
public enum QuickCapture {
    public struct Parsed: Sendable, Equatable {
        public let title: String
        public let type: WorkItemType
        public let labels: [String]
        public let priority: Priority
    }

    public static func parse(_ raw: String) -> Parsed {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var type = WorkItemType.task

        for candidate in WorkItemType.allCases where candidate != .epic {
            let prefix = "\(candidate.rawValue): "
            if text.lowercased().hasPrefix(prefix) {
                type = candidate
                text = String(text.dropFirst(prefix.count))
                break
            }
        }

        var priority = Priority.none
        if text.hasSuffix("!!") {
            priority = .urgent
            text = String(text.dropLast(2))
        } else if text.hasSuffix("!") {
            priority = .high
            text = String(text.dropLast(1))
        }

        var labels: [String] = []
        let words = text.split(separator: " ")
        var titleWords: [Substring] = []
        for word in words {
            if word.hasPrefix("#"), word.count > 1 {
                labels.append(String(word.dropFirst()))
            } else {
                titleWords.append(word)
            }
        }

        return Parsed(title: titleWords.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines),
                      type: type, labels: labels, priority: priority)
    }
}

struct TodaySurface: View {
    @Bindable var store: ProjectStore
    let theme: HostTheme
    let onOpen: (WorkItem) -> Void

    @State private var captureText = ""
    @State private var captureTarget: UUID?
    @State private var captureError: String?

    /// Merged per-project inbox results. Each project is judged against its
    /// OWN status scheme — a general-kind project's items must never be
    /// evaluated against the software ladder, or their done-ness is a lie.
    private var result: TodayInbox.Result {
        var overdue: [WorkItem] = []
        var dueToday: [WorkItem] = []
        var active: [WorkItem] = []
        var recent: [WorkItem] = []

        for project in store.activeProjects {
            guard let document = store.openProject(project.id) else { continue }
            let partial = TodayInbox.build(items: store.items(in: project.id),
                                           scheme: document.project.statusScheme, now: Date())
            overdue += partial.overdue
            dueToday += partial.dueToday
            active += partial.active
            recent += partial.recent
        }

        overdue.sort { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        dueToday.sort { $0.priority > $1.priority }
        active.sort { $0.priority > $1.priority }
        recent = Array(recent.sorted { $0.updatedAt > $1.updatedAt }.prefix(10))

        return TodayInbox.Result(overdue: overdue, dueToday: dueToday,
                                 active: active, recent: recent)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                capture
                section("Overdue", result.overdue, color: theme.statusColors.danger)
                section("Due today", result.dueToday, color: theme.statusColors.warning)
                section("In progress", result.active, color: theme.tokens.accentPrimary)
                section("Recently touched", result.recent, color: theme.tokens.accentSecondary)
            }
            .padding(16)
        }
    }

    private var capture: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Capture — e.g. bug: auth loops #backend !!", text: $captureText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submitCapture)
                Picker("", selection: $captureTarget) {
                    Text("Project").tag(UUID?.none)
                    ForEach(store.activeProjects) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                .labelsHidden()
                .frame(width: 160)
            }
            if let captureError {
                Text(captureError).font(.caption).foregroundStyle(theme.statusColors.danger)
            }
        }
    }

    private func submitCapture() {
        let parsed = QuickCapture.parse(captureText)
        guard !parsed.title.isEmpty, let projectID = captureTarget ?? store.activeProjects.first?.id
        else { return }
        // Capture files under the project's first epic, creating an "Inbox"
        // epic when there is none — a captured task with no parent would
        // violate the epic-at-root rule and be rejected.
        do {
            let epicID = try inboxEpic(in: projectID)
            var item = try store.createItem(projectID: projectID, parentID: epicID,
                                            type: parsed.type, title: parsed.title,
                                            statusID: "todo", actor: .user)
            item.labels = parsed.labels
            item.priority = parsed.priority
            try store.updateItem(item, actor: .user)
            captureText = ""
            captureError = nil
        } catch let error as QuestError {
            captureError = error.message
        } catch {
            captureError = error.localizedDescription
        }
    }

    private func inboxEpic(in projectID: UUID) throws -> UUID {
        let epics = store.items(in: projectID).filter { $0.type == .epic }
        if let inbox = epics.first(where: { $0.title == "Inbox" }) ?? epics.first { return inbox.id }
        return try store.createItem(projectID: projectID, parentID: nil, type: .epic,
                                    title: "Inbox", statusID: "todo", actor: .user).id
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [WorkItem], color: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline).foregroundStyle(color)
                ForEach(items) { item in
                    Button { onOpen(item) } label: {
                        HStack {
                            Image(systemName: icon(for: item.type))
                            Text(item.title)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.tokens.foreground)
                }
            }
        }
    }

    private func icon(for type: WorkItemType) -> String {
        switch type {
        case .epic: "flag"
        case .bug: "ant"
        case .story: "book"
        case .chore: "wrench"
        case .spike: "magnifyingglass"
        case .task: "circle"
        }
    }
}
