import Foundation

/// A repo this project's work lives in. Deliberately NOT a `Link`: a link is a
/// pointer the user clicks, while an attached repo is structural — it names
/// which connection owns it, and repo-scoped work (branches, PRs) resolves
/// against it. Multi-repo projects are the normal case, not an edge case.
public struct AttachedRepo: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    /// Which connection this repo came from. Two GitHub identities can both
    /// see an `acme/api`, and they are not the same repo.
    public var connectionID: UUID
    public var owner: String
    public var name: String
    /// Where it is checked out locally, when it is. Optional because a repo
    /// can be attached before it has ever been cloned.
    public var localPath: String?

    public var slug: String { "\(owner)/\(name)" }

    public init(id: UUID, connectionID: UUID, owner: String, name: String,
                localPath: String? = nil) {
        self.id = id
        self.connectionID = connectionID
        self.owner = owner
        self.name = name
        self.localPath = localPath
    }
}
