import Foundation

/// One project's complete persisted state: `project-<id>.json`.
public struct ProjectDocument: Codable, Sendable {
    public var project: Project
    public var items: [WorkItem]
    public var activity: [ActivityEvent]

    public init(project: Project, items: [WorkItem] = [], activity: [ActivityEvent] = []) {
        self.project = project
        self.items = items
        self.activity = activity
    }
}
