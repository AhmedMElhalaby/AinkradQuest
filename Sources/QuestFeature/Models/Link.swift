import Foundation

/// The link kinds Quest can resolve today. Unknown values decode to `.unknown`
/// so a link written by a future version is displayed rather than dropped —
/// this is what lets M2 add resolvers with no data migration.
public enum LinkScheme: String, Codable, Sendable, Hashable {
    case file, folder, url, repo, branch, pr, commit, unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LinkScheme(rawValue: raw) ?? .unknown
    }
}

public struct Link: Codable, Sendable, Hashable, Identifiable {
    /// Identity INCLUDES the repo, because a project with eleven repos routinely
    /// has `branch main` in several of them: without the repo those are one id,
    /// and removing one deletes whichever the array happened to hold first.
    /// Computed, never encoded (see `ModelCodingTests.linkIDIsNotPersisted`), so
    /// changing this formula migrates no persisted document.
    public var id: String {
        if let repo, !repo.isEmpty {
            "\(scheme.rawValue):\(repo)#\(identifier)"
        } else {
            "\(scheme.rawValue):\(identifier)"
        }
    }
    public var scheme: LinkScheme
    /// A path, URL, or repo-qualified reference. Repo-scoped schemes
    /// (`branch`, `pr`, `commit`) MUST carry their repo: a project with eleven
    /// repos cannot disambiguate "main" otherwise.
    public var identifier: String
    public var label: String
    /// Which repo a `branch`/`pr`/`commit` belongs to. Nil for other schemes.
    public var repo: String?

    public init(scheme: LinkScheme, identifier: String, label: String, repo: String? = nil) {
        self.scheme = scheme
        self.identifier = identifier
        self.label = label
        self.repo = repo
    }
}
