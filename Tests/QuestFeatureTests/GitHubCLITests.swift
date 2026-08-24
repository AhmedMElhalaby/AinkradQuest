import Foundation
import Testing
@testable import QuestFeature

/// Covers the PURE parser only — `GitHubAccountParsing.parseAccounts(_:)` — never
/// the subprocess. Shelling out to a real `gh` binary in unit tests would make
/// them flaky and environment-dependent; the thin `GitHubCLI` wrapper around
/// `Process` is exercised manually, not here.
@Suite("GitHub CLI account parsing")
struct GitHubCLITests {

    @Test("parses the real single-account payload")
    func singleAccount() throws {
        let json = """
        {
          "hosts": {
            "github.com": [
              {
                "state": "success",
                "active": true,
                "host": "github.com",
                "login": "AhmedMElhalaby",
                "tokenSource": "keyring",
                "scopes": "gist, read:org, repo, user, workflow",
                "gitProtocol": "https"
              }
            ]
          }
        }
        """
        let accounts = try GitHubAccountParsing.parseAccounts(Data(json.utf8))
        #expect(accounts.count == 1)
        let account = try #require(accounts.first)
        #expect(account.login == "AhmedMElhalaby")
        #expect(account.host == "github.com")
        #expect(account.isActive == true)
        #expect(account.isHealthy == true)
        #expect(account.scopes == ["gist", "read:org", "repo", "user", "workflow"])
        #expect(account.hasRepoScope == true)
    }

    @Test("multiple accounts on one host, one active one not")
    func multipleAccountsOneHost() throws {
        let json = """
        {
          "hosts": {
            "github.com": [
              {"state": "success", "active": true, "host": "github.com", "login": "alice", "tokenSource": "keyring", "scopes": "repo, user", "gitProtocol": "https"},
              {"state": "success", "active": false, "host": "github.com", "login": "bob", "tokenSource": "keyring", "scopes": "gist", "gitProtocol": "https"}
            ]
          }
        }
        """
        let accounts = try GitHubAccountParsing.parseAccounts(Data(json.utf8))
        #expect(accounts.count == 2)
        #expect(accounts.first { $0.login == "alice" }?.isActive == true)
        #expect(accounts.first { $0.login == "bob" }?.isActive == false)
    }

    @Test("multiple hosts including a GitHub Enterprise host")
    func multipleHosts() throws {
        let json = """
        {
          "hosts": {
            "github.com": [
              {"state": "success", "active": true, "host": "github.com", "login": "alice", "tokenSource": "keyring", "scopes": "repo", "gitProtocol": "https"}
            ],
            "github.enterprise.example.com": [
              {"state": "success", "active": true, "host": "github.enterprise.example.com", "login": "alice-work", "tokenSource": "keyring", "scopes": "repo", "gitProtocol": "https"}
            ]
          }
        }
        """
        let accounts = try GitHubAccountParsing.parseAccounts(Data(json.utf8))
        #expect(accounts.count == 2)
        #expect(Set(accounts.map(\.host)) == ["github.com", "github.enterprise.example.com"])
        // Same login on two hosts would be two distinct accounts, since `id`
        // is derived from host + login, mirroring Connection's provider scoping.
        #expect(Set(accounts.map(\.id)).count == 2)
    }

    @Test("an unhealthy account (state != success) reports isHealthy == false")
    func unhealthyAccount() throws {
        let json = """
        {
          "hosts": {
            "github.com": [
              {"state": "error", "active": true, "host": "github.com", "login": "alice", "tokenSource": "keyring", "scopes": "repo", "gitProtocol": "https"}
            ]
          }
        }
        """
        let accounts = try GitHubAccountParsing.parseAccounts(Data(json.utf8))
        #expect(accounts.first?.isHealthy == false)
    }

    @Test("scopes parse into an array, and hasRepoScope is true/false correctly")
    func scopesArray() throws {
        let jsonWithRepo = """
        {"hosts": {"github.com": [{"state": "success", "active": true, "host": "github.com", "login": "a", "tokenSource": "keyring", "scopes": "repo, gist", "gitProtocol": "https"}]}}
        """
        let jsonWithoutRepo = """
        {"hosts": {"github.com": [{"state": "success", "active": true, "host": "github.com", "login": "a", "tokenSource": "keyring", "scopes": "gist, user", "gitProtocol": "https"}]}}
        """
        let withRepo = try GitHubAccountParsing.parseAccounts(Data(jsonWithRepo.utf8))
        let withoutRepo = try GitHubAccountParsing.parseAccounts(Data(jsonWithoutRepo.utf8))
        #expect(withRepo.first?.hasRepoScope == true)
        #expect(withoutRepo.first?.hasRepoScope == false)
    }

    @Test("hosts present but empty throws the logged-out error, not a crash")
    func emptyHosts() throws {
        let json = """
        {"hosts": {}}
        """
        #expect(throws: GitHubCLIError.self) {
            try GitHubAccountParsing.parseAccounts(Data(json.utf8))
        }
        do {
            _ = try GitHubAccountParsing.parseAccounts(Data(json.utf8))
            Issue.record("expected notLoggedIn to be thrown")
        } catch let error as GitHubCLIError {
            #expect(error == .notLoggedIn)
        }
    }

    @Test("malformed JSON throws the unparsable error")
    func malformedJSON() throws {
        let data = Data("not json at all".utf8)
        do {
            _ = try GitHubAccountParsing.parseAccounts(data)
            Issue.record("expected unparsableOutput to be thrown")
        } catch let error as GitHubCLIError {
            guard case .unparsableOutput = error else {
                Issue.record("expected .unparsableOutput, got \(error)")
                return
            }
        }
    }

    @Test("an unknown extra field in the payload still parses")
    func unknownField() throws {
        let json = """
        {
          "hosts": {
            "github.com": [
              {
                "state": "success",
                "active": true,
                "host": "github.com",
                "login": "alice",
                "tokenSource": "keyring",
                "scopes": "repo",
                "gitProtocol": "https",
                "somethingGhAddedLater": {"nested": true}
              }
            ]
          }
        }
        """
        let accounts = try GitHubAccountParsing.parseAccounts(Data(json.utf8))
        #expect(accounts.count == 1)
        #expect(accounts.first?.login == "alice")
    }

    @Test("GitHubCLIError.message is non-generic and actionable for each case")
    func errorMessages() {
        #expect(GitHubCLIError.cliNotInstalled.message.localizedCaseInsensitiveContains("install"))
        #expect(GitHubCLIError.notLoggedIn.message.localizedCaseInsensitiveContains("gh auth login"))
        #expect(GitHubCLIError.commandFailed(stderr: "boom").message.contains("boom"))
        #expect(!GitHubCLIError.unparsableOutput("bad").message.isEmpty)
        // None of the messages should be Foundation's generic fallback text.
        for error in [
            GitHubCLIError.cliNotInstalled,
            .notLoggedIn,
            .commandFailed(stderr: "boom"),
            .unparsableOutput("bad"),
        ] {
            #expect(!error.message.contains("couldn't be completed"))
        }
    }
}
