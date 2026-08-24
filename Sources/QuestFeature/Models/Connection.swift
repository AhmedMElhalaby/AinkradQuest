import Foundation

/// Which backend a connection speaks to. `local` is the native tracker, which
/// is a provider like any other so that nothing above the adapter layer has to
/// special-case an unlinked project.
public enum ProviderKind: String, Codable, Sendable {
    case local, jira, linear, githubProjects
}

/// One authenticated account at one provider. Deliberately NOT a global app
/// setting: two Jira sites and three GitHub identities coexist, and each
/// project binds to exactly one of them.
public struct Connection: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var provider: ProviderKind
    /// What the user calls this account in the UI ("Work Jira").
    public var accountLabel: String
    /// What the provider calls it — email, login, workspace slug. Used to
    /// refuse a duplicate registration of the same account.
    public var accountIdentifier: String
    /// Self-hosted and per-site providers need this; Linear does not.
    public var baseURL: URL?
    /// The Keychain account key. The secret itself is NEVER stored here — this
    /// document is written to disk in the clear.
    public var credentialRef: String
    public var createdAt: Date

    public static func credentialRef(for id: UUID) -> String {
        "quest.connection.\(id.uuidString)"
    }

    public init(id: UUID, provider: ProviderKind, accountLabel: String,
                accountIdentifier: String, baseURL: URL? = nil,
                createdAt: Date = Date()) {
        self.id = id
        self.provider = provider
        self.accountLabel = accountLabel
        self.accountIdentifier = accountIdentifier
        self.baseURL = baseURL
        self.credentialRef = Self.credentialRef(for: id)
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, provider, accountLabel, accountIdentifier, baseURL, credentialRef, createdAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        // A connection written by a future Quest naming a provider this build
        // does not know decodes to `.local` rather than throwing, which would
        // take the whole registry down with it.
        let raw = try container.decode(String.self, forKey: .provider)
        provider = ProviderKind(rawValue: raw) ?? .local
        accountLabel = try container.decode(String.self, forKey: .accountLabel)
        accountIdentifier = try container.decode(String.self, forKey: .accountIdentifier)
        baseURL = try container.decodeIfPresent(URL.self, forKey: .baseURL)
        credentialRef = try container.decodeIfPresent(String.self, forKey: .credentialRef)
            ?? Self.credentialRef(for: id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}
