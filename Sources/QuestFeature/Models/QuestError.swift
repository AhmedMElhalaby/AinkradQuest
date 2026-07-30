import Foundation

/// Typed failures. Surfaced inline in the UI and as structured MCP errors, so
/// each case's `message` is written to be read by a person AND by the assistant.
public enum QuestError: Error, Equatable, Sendable {
    case projectNotFound(UUID)
    case itemNotFound(UUID)
    case parentNotFound(UUID)
    case parentIsDeleted(UUID)
    case depthExceeded(attempted: Int, maximum: Int)
    case epicMustBeRoot
    case nonEpicMustHaveParent
    case unknownStatus(String)
    /// A scheme edit would have left items pointing at a status the new scheme
    /// does not contain — the plan went stale between planning and applying.
    case schemeWouldOrphanItems(String)
    case schemeChangedUnderneath
    case cyclicParent
    case linkNotFound(String)
    case linkAlreadyExists(String)

    public var message: String {
        switch self {
        case .projectNotFound(let id): "No project with id \(id)."
        case .itemNotFound(let id): "No work item with id \(id)."
        case .parentNotFound(let id): "No parent work item with id \(id)."
        case .parentIsDeleted(let id):
            "Work item \(id) is in the trash. Restore it before filing work under it."
        case .depthExceeded(let attempted, let maximum):
            "Hierarchy is capped at \(maximum) levels (epic → item → subtask); this would make \(attempted)."
        case .epicMustBeRoot: "An epic cannot have a parent."
        case .nonEpicMustHaveParent: "Only epics may sit at the top level of a project."
        case .unknownStatus(let id): "Status '\(id)' is not in this project's status scheme."
        case .schemeWouldOrphanItems(let id):
            "Items still hold status '\(id)', which the new scheme does not contain — "
            + "the project changed since this scheme edit was worked out. "
            + "Nothing was changed; review the scheme again."
        case .schemeChangedUnderneath:
            "This project's statuses changed since these edits were planned. "
            + "Review the current statuses and apply again."
        case .cyclicParent: "An item cannot be moved under its own descendant."
        case .linkNotFound(let id): "No link \(id) on that project or item."
        case .linkAlreadyExists(let id):
            "Link \(id) is already attached to that project or item."
        }
    }
}
