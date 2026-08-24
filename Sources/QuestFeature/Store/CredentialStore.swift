import Foundation

public enum CredentialError: Error, Equatable {
    case keychain(OSStatus)
}

/// The seam that keeps secrets out of documents. Everything above it — the
/// registry, the UI, the future adapters — asks for a secret by ref and never
/// learns where it is kept.
public protocol CredentialStore: Sendable {
    func secret(forRef ref: String) -> String?
    /// Passing `nil` deletes the entry. Throws when the underlying store
    /// refused the write: a silently-lost credential looks exactly like a
    /// revoked token later, which is a miserable thing to debug.
    func setSecret(_ secret: String?, forRef ref: String) throws
}

/// Test double. Keeps registry tests off the real Keychain, which would
/// otherwise prompt and pollute the developer's login keychain.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    public init() {}
    public func secret(forRef ref: String) -> String? { storage[ref] }
    public func setSecret(_ secret: String?, forRef ref: String) throws {
        if let secret { storage[ref] = secret } else { storage.removeValue(forKey: ref) }
    }
}
