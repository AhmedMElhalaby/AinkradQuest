import Foundation
import AppKit

public enum LinkOpenError: Error, Equatable {
    case missingTarget(path: String)

    public var message: String {
        switch self {
        case .missingTarget(let path): "Nothing exists at \(path) any more."
        }
    }
}

/// The side-effecting edge of link opening, behind a protocol so the click path
/// is testable without opening a real Finder window.
@MainActor public protocol LinkOpener {
    func reveal(_ url: URL) throws
    func openFolder(_ url: URL) throws
    func openWeb(_ url: URL) throws
}

/// The production opener.
///
/// This works without any security-scoped access because the Ainkrad host
/// carries no `com.apple.security.app-sandbox` entitlement (only
/// `com.apple.security.cs.disable-library-validation`). That is a deliberate,
/// recorded trade — see the M4 design. If Ainkrad ever adopts the sandbox,
/// opening files and folders outside a granted root will start failing, and
/// per-attachment security-scoped bookmarks (removed in M3 because nothing read
/// them) come back, with this type as the reader that justifies them.
@MainActor public struct WorkspaceLinkOpener: LinkOpener {
    public init() {}

    public func reveal(_ url: URL) throws {
        try requireExists(url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func openFolder(_ url: URL) throws {
        try requireExists(url)
        NSWorkspace.shared.open(url)
    }

    public func openWeb(_ url: URL) throws {
        NSWorkspace.shared.open(url)
    }

    /// A link outlives the thing it points at: folders get moved, volumes get
    /// unmounted. Checking first turns a silent no-op into a message.
    private func requireExists(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LinkOpenError.missingTarget(path: url.path)
        }
    }
}

/// Routes a link through `LinkResolution` and performs the result.
/// Returns a reason when there was nothing to do, so the caller can show it.
@MainActor public enum LinkOpening {
    @discardableResult
    public static func open(_ link: Link, using opener: some LinkOpener) throws -> String? {
        switch LinkResolution.route(for: link) {
        case .reveal(let url): try opener.reveal(url); return nil
        case .openFolder(let url): try opener.openFolder(url); return nil
        case .web(let url): try opener.openWeb(url); return nil
        case .inert(let reason): return reason
        }
    }
}
