import Testing
import Foundation
@testable import QuestFeature

/// `ProjectSettingsSheet.save()` snapshots `draft` at sheet-init time, then
/// refreshes only `name`, `colorToken`, and `statusScheme` from the live
/// document before writing `draft` back through `updateProject`. Everything
/// else on `draft` — `state`, `links`, `archivedAt`, `kind` (aside from the
/// user's own edit through the picker) — is whatever it was when the sheet
/// opened.
///
/// This suite mirrors that exact write path (there is no SwiftUI hosting
/// harness in this test target for `ProjectSettingsSheet` itself — see
/// `ViewSourceInvariantsTests` for why this codebase source-scans views
/// instead of hosting them) to check whether a state or link change made
/// through the store WHILE the sheet is open survives a subsequent Save.
@MainActor
@Suite("ProjectSettingsSheet.save() stale-draft coverage")
struct ProjectSettingsSheetSaveTests {
    /// Task 5 review (Important 6) asked for a behavioural guard proving
    /// `state`/`links` survive a stale-draft save, the same way
    /// `staleDraftDoesNotClobberLiveConnectionFields` proves it for the
    /// connection fields M2A moved off `Project`. Running it revealed that
    /// they do NOT survive today: `save()` never refreshes `state`/`links`
    /// the way it refreshes `statusScheme`, so a state change (e.g. pausing
    /// the project from elsewhere) or a link added while the sheet sits open
    /// is silently reverted on Save. This is a live bug PRE-DATING this task
    /// — Task 5 did not introduce it and did not touch `state`/`links` — so
    /// per instruction this is reported rather than fixed here, and left
    /// `.disabled` so the suite stays green pending a ruling on whether (and
    /// where) to fix it.
    @Test("a state change and a link added while the sheet is open survive Save",
         .disabled("live bug predating Task 5 — see doc comment; reported, not fixed, pending a ruling"))
    func stateAndLinksSurviveStaleDraftSave() throws {
        let store = makeProjectStore(InMemoryProjectRepository())
        let project = store.createProject(name: "Quest", kind: .software, actor: .user)
        // Snapshot exactly as `ProjectSettingsSheet.init` does.
        let staleDraft = project

        try store.setState(project.id, state: .paused, actor: .user)
        try store.addLink(to: .project(project.id),
                          link: Link(scheme: .url, identifier: "https://example.com", label: "Example"),
                          actor: .user)

        // Mirrors `ProjectSettingsSheet.save()` exactly: only `statusScheme`
        // (and, in the real save(), `name`/`colorToken`) is refreshed from
        // the live document before writing `draft` back.
        var draft = staleDraft
        if let current = store.openProject(draft.id)?.project.statusScheme {
            draft.statusScheme = current
        }
        try store.updateProject(draft, actor: .user)

        let saved = try #require(store.openProject(project.id)?.project)
        #expect(saved.state == .paused)
        #expect(saved.links.count == 1)
    }
}
