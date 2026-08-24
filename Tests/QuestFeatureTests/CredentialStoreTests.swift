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

    @Test("refs are isolated from one another")
    func isolation() throws {
        let store = InMemoryCredentialStore()
        try store.setSecret("a", forRef: "quest.connection.A")
        try store.setSecret("b", forRef: "quest.connection.B")
        #expect(store.secret(forRef: "quest.connection.A") == "a")
        #expect(store.secret(forRef: "quest.connection.B") == "b")
    }
}
