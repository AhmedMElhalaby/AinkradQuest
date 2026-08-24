import Testing
import Foundation
@testable import QuestFeature

@Suite("Credential store")
struct CredentialStoreTests {
    @Test("a stored secret reads back by ref")
    func roundTrip() throws {
        let store = InMemoryCredentialStore()
        try store.setSecret("token-abc", forRef: "quest.connection.A")
        #expect(store.secret(forRef: "quest.connection.A") == "token-abc")
    }

    @Test("a nil secret deletes the entry")
    func delete() throws {
        let store = InMemoryCredentialStore()
        try store.setSecret("token-abc", forRef: "quest.connection.A")
        try store.setSecret(nil, forRef: "quest.connection.A")
        #expect(store.secret(forRef: "quest.connection.A") == nil)
    }

    @Test("a keychain failure's message is not Foundation's generic localizedDescription string")
    func keychainErrorHasAReadableMessage() {
        let error = CredentialError.keychain(-25291) // errSecNotAvailable
        #expect(error.message.contains("-25291"))
        #expect(!error.message.contains("couldn't be completed"))
        #expect((error as any Error).localizedDescription == error.message)
    }

    @Test("refs are isolated from one another")
    func isolation() throws {
        let store = InMemoryCredentialStore()
        try store.setSecret("a", forRef: "quest.connection.A")
        try store.setSecret("b", forRef: "quest.connection.B")
        #expect(store.secret(forRef: "quest.connection.A") == "a")
        #expect(store.secret(forRef: "quest.connection.B") == "b")
    }
}
