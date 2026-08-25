import Foundation

/// What state the overlay store is in, as a TYPE rather than a string.
///
/// `persistenceFailure` carried three conditions distinguishable only by their
/// message text, and any later successful write cleared it — so a warning about
/// an unresolved problem could vanish before the user acted on it. A surface
/// that must disable editing needs to ask a question, not parse prose.
public enum OverlayHealth: Equatable, Sendable {
    case healthy
    /// A project's overlay document exists but could not be decoded. Writes for
    /// it are blocked so the corrupt bytes are not overwritten with empty state.
    case unreadable(UUID)
    /// A write was refused because that project is unreadable.
    case writeBlocked(UUID)
    /// An ordinary write failure. Retryable, unlike the two above.
    case writeFailed(String)

    /// Whether editing should be disabled. Only an unreadable overlay is
    /// genuinely read-only; a failed write keeps the change in memory and can
    /// be retried.
    public var isReadOnly: Bool {
        switch self {
        case .unreadable, .writeBlocked: true
        case .healthy, .writeFailed: false
        }
    }

    public var message: String? {
        switch self {
        case .healthy: nil
        case .unreadable(let id):
            QuestError.overlayCorrupt(id).message
        case .writeBlocked:
            "That project's saved notes could not be read, so nothing new was saved over them. "
                + "Restore it from a backup in Quest's settings, or discard it to start fresh."
        case .writeFailed(let reason):
            "Your notes and priorities could not be saved: \(reason)"
        }
    }
}
