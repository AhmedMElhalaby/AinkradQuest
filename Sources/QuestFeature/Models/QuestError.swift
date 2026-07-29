import Foundation

/// Typed failures. Surfaced inline in the UI and as structured MCP errors, so
/// each case's `message` is written to be read by a person AND by the assistant.
public enum QuestError: Error, Equatable, Sendable {
    case projectNotFound(UUID)
    case itemNotFound(UUID)
    case parentNotFound(UUID)
    case depthExceeded(attempted: Int, maximum: Int)
    case epicMustBeRoot
    case nonEpicMustHaveParent
    case unknownStatus(String)
    case cyclicParent
    case linkNotFound(String)
    case linkAlreadyExists(String)

    public var message: String {
        switch self {
        case .projectNotFound(let id): "No project with id \(id)."
        case .itemNotFound(let id): "No work item with id \(id)."
        case .parentNotFound(let id): "No parent work item with id \(id)."
        case .depthExceeded(let attempted, let maximum):
            "Hierarchy is capped at \(maximum) levels (epic → item → subtask); this would make \(attempted)."
        case .epicMustBeRoot: "An epic cannot have a parent."
        case .nonEpicMustHaveParent: "Only epics may sit at the top level of a project."
        case .unknownStatus(let id): "Status '\(id)' is not in this project's status scheme."
        case .cyclicParent: "An item cannot be moved under its own descendant."
        case .linkNotFound(let id): "No link \(id) on that project or item."
        case .linkAlreadyExists(let id):
            "Link \(id) is already attached to that project or item."
        }
    }
}
