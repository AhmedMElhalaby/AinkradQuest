import Foundation
import AinkradAppKit

/// Dispatches one MCP call onto the store.
///
/// The store is the only thing this type touches, so every guarantee the store
/// enforces — depth cap, status validity, activity logging, soft delete —
/// applies identically whether a call came from the assistant or from a view.
/// Nothing here reimplements a rule.
@MainActor
public final class QuestMCPOperations {
    private let store: ProjectStore

    public init(store: ProjectStore) { self.store = store }

    public func run(operation: String, arguments: String) async -> AgentActionResult {
        guard let data = arguments.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return failure("\(operation): arguments must be a JSON object")
        }
        do {
            return switch operation {
            case "listProjects": listProjects()
            case "getProject": try getProject(json)
            case "searchItems": searchItems(json)
            case "getItem": try getItem(json)
            case "createProject": createProject(json)
            case "updateProject": try updateProject(json)
            case "createItem": try createItem(json)
            case "updateItem": try updateItem(json)
            case "moveItem": try moveItem(json)
            case "setStatus": try setStatus(json)
            case "deleteItem": try deleteItem(json)
            case "deleteProject": try deleteProject(json)
            default: failure("Unknown operation \(operation)")
            }
        } catch let error as ArgumentError {
            return failure(error.message)
        } catch let error as QuestError {
            return failure(error.message)
        } catch {
            return failure(error.localizedDescription)
        }
    }

    // MARK: reads

    private func listProjects() -> AgentActionResult {
        let lines = store.projects.map { "\($0.id.uuidString)  \($0.name)  [\($0.state.rawValue)]" }
        return success(lines.isEmpty ? "No projects." : lines.joined(separator: "\n"))
    }

    private func getProject(_ json: [String: Any]) throws -> AgentActionResult {
        let id = try uuid(json, "projectID", operation: "getProject")
        guard let document = store.openProject(id) else { throw QuestError.projectNotFound(id) }
        let statuses = document.project.statusScheme.statuses.map(\.id).joined(separator: ", ")
        let items = document.items.filter { !$0.isDeleted }
            .map { describe($0, scheme: document.project.statusScheme) }
        return success("""
            \(document.project.name) [\(document.project.kind.rawValue)]
            statuses: \(statuses)
            links: \(document.project.links.map(\.label).joined(separator: ", "))
            items:
            \(items.joined(separator: "\n"))
            """)
    }

    private func searchItems(_ json: [String: Any]) -> AgentActionResult {
        var filter = ItemFilter()
        filter.text = json["query"] as? String ?? ""
        if let raw = json["statusID"] as? String { filter.statusIDs = [raw] }
        let projectIDs = (json["projectID"] as? String).flatMap(UUID.init(uuidString:))
            .map { [$0] } ?? store.projects.map(\.id)

        var lines: [String] = []
        for projectID in projectIDs {
            guard let document = store.openProject(projectID) else { continue }
            let matched = ItemQuery.apply(filter, sort: .updated, to: document.items,
                                          scheme: document.project.statusScheme)
            lines += matched.map { "\(document.project.name): " + describe($0, scheme: document.project.statusScheme) }
        }
        return success(lines.isEmpty ? "No matching items." : lines.joined(separator: "\n"))
    }

    private func getItem(_ json: [String: Any]) throws -> AgentActionResult {
        let id = try uuid(json, "itemID", operation: "getItem")
        guard let projectID = store.projectID(owning: id),
              let document = store.openProject(projectID),
              let item = document.items.first(where: { $0.id == id })
        else { throw QuestError.itemNotFound(id) }
        return success("""
            \(item.title)
            id: \(item.id.uuidString)
            type: \(item.type.rawValue)  status: \(item.statusID)  priority: \(item.priority)
            labels: \(item.labels.joined(separator: ", "))
            due: \(item.dueDate.map(String.init(describing:)) ?? "none")
            body:
            \(item.body)
            """)
    }

    // MARK: writes — every one of them records `actor: .agent`

    private func createProject(_ json: [String: Any]) -> AgentActionResult {
        let name = json["name"] as? String ?? "Untitled"
        let kind = ProjectKind(rawValue: json["kind"] as? String ?? "software") ?? .software
        let project = store.createProject(name: name, kind: kind, actor: .agent)
        return success("Created project \(project.name) (\(project.id.uuidString))")
    }

    private func updateProject(_ json: [String: Any]) throws -> AgentActionResult {
        let id = try uuid(json, "projectID", operation: "updateProject")
        guard var document = store.openProject(id) else { throw QuestError.projectNotFound(id) }
        if let name = json["name"] as? String { document.project.name = name }
        if let summary = json["summary"] as? String { document.project.summaryText = summary }
        try store.updateProject(document.project, actor: .agent)
        return success("Updated project \(document.project.name)")
    }

    private func createItem(_ json: [String: Any]) throws -> AgentActionResult {
        let projectID = try uuid(json, "projectID", operation: "createItem")
        let parentID = (json["parentID"] as? String).flatMap(UUID.init(uuidString:))
        let type = WorkItemType(rawValue: json["type"] as? String ?? "task") ?? .task
        let title = json["title"] as? String ?? "Untitled"
        let statusID = json["statusID"] as? String ?? "todo"
        let item = try store.createItem(projectID: projectID, parentID: parentID, type: type,
                                        title: title, statusID: statusID, actor: .agent)
        return success("Created \(type.rawValue) \(item.title) (\(item.id.uuidString))")
    }

    private func updateItem(_ json: [String: Any]) throws -> AgentActionResult {
        let id = try uuid(json, "itemID", operation: "updateItem")
        guard let projectID = store.projectID(owning: id),
              let document = store.openProject(projectID),
              var item = document.items.first(where: { $0.id == id })
        else { throw QuestError.itemNotFound(id) }
        if let title = json["title"] as? String { item.title = title }
        if let body = json["body"] as? String { item.body = body }
        if let labels = json["labels"] as? [String] { item.labels = labels }
        if let raw = json["priority"] as? Int, let priority = Priority(rawValue: raw) {
            item.priority = priority
        }
        try store.updateItem(item, actor: .agent)
        return success("Updated \(item.title)")
    }

    private func moveItem(_ json: [String: Any]) throws -> AgentActionResult {
        let id = try uuid(json, "itemID", operation: "moveItem")
        let parentID = (json["parentID"] as? String).flatMap(UUID.init(uuidString:))
        let orderIndex = json["orderIndex"] as? Int ?? 0
        try store.moveItem(id, toParent: parentID, orderIndex: orderIndex, actor: .agent)
        return success("Moved item \(id.uuidString)")
    }

    private func setStatus(_ json: [String: Any]) throws -> AgentActionResult {
        let id = try uuid(json, "itemID", operation: "setStatus")
        guard let statusID = json["statusID"] as? String else {
            throw ArgumentError(message: "setStatus: missing or invalid argument 'statusID'")
        }
        try store.setStatus(id, statusID: statusID, actor: .agent)
        return success("Set \(id.uuidString) to \(statusID)")
    }

    private func deleteItem(_ json: [String: Any]) throws -> AgentActionResult {
        let id = try uuid(json, "itemID", operation: "deleteItem")
        try store.deleteItem(id, actor: .agent)
        return success("Moved item \(id.uuidString) to trash. It can be restored from Quest.")
    }

    private func deleteProject(_ json: [String: Any]) throws -> AgentActionResult {
        let id = try uuid(json, "projectID", operation: "deleteProject")
        try store.deleteProject(id, actor: .agent)
        return success("Moved project \(id.uuidString) to trash. It can be restored from Quest.")
    }

    // MARK: helpers

    /// A missing or unparseable id argument is the caller's mistake, not "no
    /// such item" — reporting it as `itemNotFound` would hand the assistant a
    /// fabricated random id and mislabel "you forgot an argument" as "that
    /// item does not exist", which it cannot act on. This throws a distinct
    /// error naming the operation and the key instead. A well-formed id that
    /// simply doesn't resolve to anything is still reported by the caller as
    /// `QuestError.itemNotFound`/`projectNotFound`.
    private func uuid(_ json: [String: Any], _ key: String, operation: String) throws -> UUID {
        guard let raw = json[key] as? String, let id = UUID(uuidString: raw) else {
            throw ArgumentError(message: "\(operation): missing or invalid argument '\(key)'")
        }
        return id
    }

    /// Renders the status's display name (from the project's own scheme)
    /// rather than its raw id, which is what the assistant needs to reason
    /// about the item without a second lookup.
    private func describe(_ item: WorkItem, scheme: StatusScheme) -> String {
        let statusName = scheme.status(id: item.statusID)?.name ?? item.statusID
        return "\(item.id.uuidString)  [\(item.type.rawValue)/\(statusName)]  \(item.title)"
    }

    private func success(_ text: String) -> AgentActionResult {
        AgentActionResult(text: text, isError: false)
    }

    private func failure(_ text: String) -> AgentActionResult {
        AgentActionResult(text: text, isError: true)
    }
}

/// A malformed or missing call argument — distinct from `QuestError`, which
/// reports domain state (e.g. "no such item") the store already knows about.
private struct ArgumentError: Error {
    let message: String
}
