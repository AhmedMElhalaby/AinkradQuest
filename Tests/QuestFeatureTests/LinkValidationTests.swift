import Testing
@testable import QuestFeature

@Suite("LinkValidation")
struct LinkValidationTests {
    @Test("a repo-scoped link without a repo is refused")
    func repoRequired() {
        let result = LinkValidation.normalize(scheme: .branch, identifier: "main",
                                              label: "main", repo: nil)
        #expect(result.isFailure)
    }

    @Test("a repo-scoped link with a repo is accepted and keeps it")
    func repoKept() throws {
        let link = try #require(LinkValidation.normalize(
            scheme: .pr, identifier: "42", label: "PR 42", repo: "optimus-api").value)
        #expect(link.repo == "optimus-api")
    }

    @Test("an empty identifier is refused for every scheme")
    func emptyIdentifier() {
        #expect(LinkValidation.normalize(scheme: .url, identifier: "  ",
                                         label: "x", repo: nil).isFailure)
    }

    @Test("a missing label falls back to the identifier rather than being blank")
    func labelFallback() throws {
        let link = try #require(LinkValidation.normalize(
            scheme: .folder, identifier: "~/Projects/quest", label: "", repo: nil).value)
        #expect(link.label == "~/Projects/quest")
    }
}
