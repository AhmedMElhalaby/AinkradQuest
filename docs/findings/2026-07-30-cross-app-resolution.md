# Finding — Cross-app link resolution

**Date:** 2026-07-30
**Status:** Investigation complete. Recommendation below; no code was changed.
**Scope:** Read-only pass over `AinkradAppKit`, `Ainkrad` (host), `GitMage`, `AinkradLore`, `AinkradLeyline`, `AinkradTerminal`, and Quest itself.

Quest's positioning is "own tasks, federate the rest": it owns work items and links out to
documents, repos, PRs, and hosts. Today it **stores and displays** links but cannot **open**
them in the owning app. This finding answers what that would take.

## 1. What exists today

**One mechanism: a host-owned, one-slot-per-app payload mailbox, plus "open a pane".**

- `PluginAppLauncher` is the entire contract — `open(appID:payload:)` and
  `takePendingLaunch() -> String?`
  (`AinkradAppKit/Sources/AinkradAppKitContract/AppLaunch.swift:7-13`). The payload is an
  **opaque String**; its encoding is a bilateral agreement between two apps.
- Reached through `HostServices.apps` (`.../HostServices.swift:36`).
- Generation 8 added outcome reporting on a separate, cast-discovered protocol:
  `PluginAppLauncherResult.openReportingOutcome` returning
  `.opened / .unknownApp / .disabled / .refused(reason:)`
  (`.../SSHLaunchPayload.swift:108-124`).
- Host side: `HostAppLauncher` checks availability, enqueues, requests open
  (`Ainkrad/Sources/AinkradHostRuntime/HostAppLauncher.swift:29-45`). The mailbox is
  `PluginLaunchHub` — `pending: [String: String]`, one entry per appID, replaced by a newer
  launch, cleared on take (`.../PluginLaunchHub.swift:9,52,56-59`).
- The one working end-to-end instance is **Leyline → Terminal**, over the shared, versioned,
  validate-on-decode `SSHLaunchPayload` (`SSHLaunchPayload.swift:24-98`). Sender:
  `AinkradLeyline/.../Views/LeylineRootView.swift:150-187`. Receiver:
  `AinkradTerminal/.../Views/TerminalBlockRootView.swift:34-38` (`takeLaunch()` on
  `onAppear`, only when `session == nil`).

### Limits, all observed in code

1. **A payload can already address a resource.** `SSHLaunchPayload` *is* a resource address.
   Expressiveness is not the gap — **receivers** are.
2. **Depth-1 mailbox per appID.** Two rapid launches at one target lose the first
   (`PluginLaunchHub.swift:52`).
3. **Delivery is tied to a fresh pane's `onAppear`.** `TileLayout.openApp` always appends a
   new Block and never focuses an existing pane (`.../Windowing/TileLayout.swift:82-88`);
   `PluginLaunchHub.isOpen` exists (`:50`) but the open handler ignores it
   (`AppEnvironment+BootstrapFinalize.swift:175-185`). So clicking a Quest link would open a
   **second** Git Mage pane every time.
4. **No app-to-app query.** `AgentActionProvider` exposes only `register`/`remove`
   (`AgentAction.swift:30-34`); `invoke` lives on the host-only `AgentActionRegistryHub`
   (`.../AgentActionRegistryHub.swift:34-37`). Quest can *launch* another app but cannot
   *ask* it anything. MCP is a host↔agent surface, not plugin↔plugin
   (`MCPAppServer.swift:10-15`).
5. **No URI or registry layer exists.** No `ainkrad://` scheme anywhere (grepped both
   `Ainkrad/Sources` and `AinkradAppKit/Sources`).
6. `.refused(reason:)` is declared but never produced by `HostAppLauncher` — inference: a
   dead case today.

## 2. What is missing, and where the gap lives

| Capability | Gap lives in |
|---|---|
| Carry a resource address app→app | **Nowhere — already exists** (opaque payload + `SSHLaunchPayload` precedent) |
| Deliver to an already-open pane rather than spawning another | **Host** — `TileLayout.openApp` + open handler; `isOpen` already available |
| Two payloads in flight to one target | **Host** — single-slot `PluginLaunchHub.pending` |
| A shared payload type so sender and receiver cannot drift | **SDK contract** — one `Codable` type per resource kind |
| Actually opening the resource | **Target app, every time.** Git Mage and Lore call `takePendingLaunch` **nowhere** (only test fakes, e.g. `GitMage/Tests/.../GitMageContextRegistrationTests.swift:35`) |
| Ask another app to resolve without opening it | **SDK contract** — no plugin-callable `invoke`. Not needed for slice 1 |
| Sending at all, from Quest | **Quest** — `QuestApp.makeRootView` never threads `host.apps` into the view tree (`QuestApp.swift:39-41`) |

## 3. Per-app cost

### Git Mage — repo: cheap. Branch: medium. PR: expensive.

- Resource identity is `GitMageRepoConfig` keyed by **absolute path**
  (`GitMage/Sources/GitMageFeature/GitMageModels.swift:17-40`).
- **The receive-and-act hook already exists:** `GitMageViewModel.openRepositoryPath(_:)` →
  `registerRepository(path:)`, which adds-or-reselects, activates, persists, refreshes
  (`GitMageViewModel.swift:214-216, 191-210`). Quest's repo links already store `url.path`,
  so the identifier is already the right shape.
- To implement: decode a payload plus one `takePendingLaunch()` call in `GitMageShell`
  (which already holds `host` — `Views/GitMageShell.swift:5,18-22`), then
  `model.openRepositoryPath(path)`. ~30 lines plus tests.
- Branch: no `checkout(named:)` exists — only `checkoutSelectedBranch()`
  (`GitMageViewModel.swift:302`) — so it needs a new entry point, and checkout can fail on a
  dirty tree, which needs a surfaced error.
- PR: needs `selectedArea = .pullRequests` plus `await prModel.select(number)`
  (`PullRequestsViewModel.swift:114-125`), and `prModel` is per-pane `@State` gated on a
  GitHub remote and auth (`GitMageShell.swift:8-9`). Do not attempt first.
- **Hazard:** the plugin's document store is one per app instance, but `GitMageViewModel` is
  per-pane `@StateObject`, so two panes both write `library.state.v2`
  (`GitMageWorkspaceStore.swift:6,30-33`). Combined with limit #3 (always a new pane),
  "open at repo" would flip `activeRepoID` under the older pane. **This is why the host-side
  pane-reuse fix matters more than the app-side work.**

### Lore — note: cheapest of the three.

- Identity is the note's file `URL` (`Models/Note.swift:10`). Entry points already exist:
  `open(url:)` dedupes by canonical path, opens a tab, records `openError`
  (`Store/LoreStore.swift:253-271`), and `openLink(_:)` handles wikilink targets (`:135-140`).
- To implement: pass a `takeLaunch` closure from `LoreApp.makeRootView` (`LoreApp.swift:69-71`)
  into `LoreRootView`, call `store.open(url:)`. ~20 lines.
- `LoreStore` is shared per instance (`LoreApp.swift:37-44`), so an already-open Lore pane
  *does* show the new tab — Lore does not suffer Git Mage's split-brain.

### Leyline — host session: correct architecture, least urgent.

- Leyline → Terminal already works (`LeylineRootView.swift:150-187`). What Quest lacks is
  the data: a Quest link identifier is a string, not `{host, port, username, identityFile}`,
  and Quest must never hold key material.
- Right shape: Quest → Leyline payload `{kind:"connection", id-or-label}`; Leyline resolves
  via the same `ConnectionAddress.resolve` rule its bridge and `connect` tool share
  (`Host/LeylineConnectionBridge.swift:84-97`), then forwards to Terminal. Needs Leyline's
  first `takePendingLaunch`.
- Wrong shape: Quest resolving and connecting itself — impossible today (gap #4) and
  undesirable, since the bridge's reply carries `identityPath` to a plaintext private key and
  is deliberately host-only (`LeylineConnectionBridge.swift:16-27`).

## 4. Recommendation — the smallest useful slice

**Ship exactly this: `repo` links open Git Mage at that repo, via a new shared
`RepoLaunchPayload` in the SDK contract. Nothing else.**

1. **`AinkradAppKitContract`:** `RepoLaunchPayload {kind:"repo", version, path}` with
   `validated()` (reject empty or relative paths, reject a leading `-`), modelled
   line-for-line on `SSHLaunchPayload.swift:24-98` including its "absent version decodes as
   1" rule (`:54-56`).
2. **Quest:** thread `host.apps` into `LinkListView`; make a `.repo` row clickable →
   `openReportingOutcome(appID: "gitmage", payload:)`, rendering
   `.unknownApp/.disabled/.refused` inline exactly as Leyline does
   (`LeylineRootView.swift:177-187`). `LinkListView` already has an inline `error` slot
   (`Views/LinkEditor.swift:93,114-116`).
3. **Git Mage:** consume in `GitMageShell` on first appearance →
   `model.openRepositoryPath(path)`.
4. **Host, in the same slice — not after:** focus an existing pane when `isOpen(appID)`
   rather than appending a Block (`AppEnvironment+BootstrapFinalize.swift:175-185`,
   `TileLayout.swift:82-88`), and give a live pane a way to consume a payload. Without this,
   the most common case — Git Mage already open — either does nothing or corrupts the other
   pane's active repo. **This is what makes it a feature rather than a demo.**

**Worth doing before anything larger: yes.** It is the only slice where every side already
has its hook, it forces the host fix that every future resolver needs, and it validates the
payload-type discipline before three more kinds are minted. Do **not** build a generic URI
registry, a resolver protocol, or PR/branch/note/host resolution first. Honest sequencing:
**repo → (pane reuse proven) → note → branch → PR → Leyline connection.**

## 5. What Quest changes — and does the no-migration claim hold?

**Yes, and more strongly than the M1 design realised.** The M1 spec claimed unknown schemes
are stored and displayed but not opened, so resolvers arrive without a data migration.
Verified:

- `LinkScheme.init(from:)` maps any unrecognised raw value to `.unknown`
  (`Models/Link.swift:9-12`) — a link written by a newer Quest survives an older one.
- `Link.id` is computed and never encoded (`Link.swift:21-27`, pinned by
  `ModelCodingTests.linkIDIsNotPersisted`) — identity changes migrate nothing.
- For `.repo`/`.folder`, `identifier` is **already an absolute filesystem path**, because
  `FolderAttachment.attach` normalizes with `identifier: url.path`
  (`Views/AttachmentSuggestions.swift:47`) and `FolderMatch.linkKind` decides `.repo` by the
  presence of `.git` (`Logic/FolderMatch.swift:21-24`). That is exactly what Git Mage keys
  repos on. **Zero migration, no reinterpretation of stored values.**

Quest's resolver layer should be one pure function plus one thin sender:

- `LinkResolution.route(for: Link) -> Route?`, where `Route` is
  `.launch(appID:payload:) / .reveal(URL) / .web(URL) / .none` — a pure switch on `scheme`,
  unit-testable with no host.
- `.file`/`.folder`/`.url` need **no cross-app work at all**: `NSWorkspace` handles them
  in-process (Lore's precedent: `activateFileViewerSelecting` in
  `Documents/Fallback/FallbackViewer.swift:21`). Inference: that makes 3 of 7 schemes
  resolvable with no SDK or host change — arguably a cheaper zeroth slice, but it does not
  prove the cross-app path, which is the point.
- `.unknown` must stay inert and visible (`LinkSymbol.name` already renders `questionmark`,
  `LinkEditor.swift:144`).

## 6. Two defects found in passing

Unrelated to the spike, surfaced while reading:

1. **Orphaned attachment bookmarks.** `FolderAttachment.attach` saves the security-scoped
   bookmark under `FolderBookmark.attachmentKey(UUID())` — a freshly minted UUID that is
   never persisted (`AttachmentSuggestions.swift:54`; key builder
   `Store/FolderBookmark.swift:15`). No reader ever resolves an `attachmentKey`. So every
   attachment writes an unreachable blob that accumulates forever, and the bookmark it was
   meant to preserve cannot be recovered. Must be keyed by something stable — the link's own
   id — if a resolver is ever to need scoped access.
2. **A misleading comment.** `FolderBookmark`'s doc comment asserts "Ainkrad plugins are
   sandboxed" (`FolderBookmark.swift:6`), but the host's entitlements contain only
   `com.apple.security.cs.disable-library-validation` — no `com.apple.security.app-sandbox`
   (`Ainkrad/config/Ainkrad.entitlements:26-27`). Inference: bookmarks are currently
   belt-and-braces rather than required. Not a reason to remove them, but the comment
   overstates the constraint.

## 7. Open questions for the owner

1. **Pane reuse or new pane — which is intended?** `isOpen` was added for the MCP activator
   and deliberately not used by the open handler. Was "always a new pane" a decision or an
   omission? This decides whether slice-1 item #4 is a bug fix or a behaviour change.
2. **How should a live pane be notified of a payload?** Consumption is `onAppear`-only today.
   Options: a host-published environment signal (the `ainkradPaneIsFocused` pattern,
   `PluginFocus.swift:28-33`), or a new cast-discovered SDK protocol. Both are contract
   changes.
3. **Does Git Mage's two-panes-one-document write conflict already bite?** The code path is
   real; whether it is reachable in practice was not tested.
4. **Is a `repo` link's identifier guaranteed to be a path?** Confirmed for links created
   through `FolderAttachment`, but `LinkEditor` lets a user type anything for `.repo`
   (`LinkEditor.swift:41,50,53`). The resolver needs a policy: refuse visibly, or name-match
   against Git Mage's library (which needs the query capability Quest lacks).
5. **Which scheme should a Leyline connection link use?** `.unknown` tolerates a future
   `host`/`connection` scheme with no migration, but no such case exists in `LinkScheme`.

## Coverage note

Read fully: the seven named `AinkradAppKitContract` files plus `AppLaunch`,
`SSHLaunchPayload`, `AinkradAPI`, `AinkradApp`; `HostAppLauncher`, `PluginLaunchHub`,
`AgentActionRegistryHub`, `HostServicesImpl` (first 80 lines), `Ainkrad.entitlements`;
`LeylineConnectionBridge`, `LeylineApp`, `LeylineConnection`, `LeylineCatalog`;
`TerminalApp`, `SSHLaunch`; Quest's `Link`, `LinkTarget`, `LinkEditor`, `FolderMatch`,
`FolderBookmark`, `QuestApp`.

Read in part: the two `AppEnvironment+Bootstrap*` files, `TileLayout`, `GitMageViewModel`,
`GitMageShell`, `PullRequestsViewModel`, `GitMageModels`, `LoreStore`, `LoreRootView`,
Quest's `AttachmentSuggestions`, `OverviewSurface`, `QuestRootView`, the M1 design spec.

Not inspected: all test suites; `AinkradKit`; `AinkradCatalog`; `SwiftTerm`; Git Mage's
Forge/MCP/Settings/UI trees; Lore's Documents/MCP/Logic and index layer; Leyline's MCP
operations and key resolvers beyond signatures; the host's plugin loader, workspace manager
and agent tool layer beyond the greps cited. Nothing was built, run, or launched.
