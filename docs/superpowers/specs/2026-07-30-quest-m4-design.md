# Quest — M4 Design (In-Process Link Opening)

**Date:** 2026-07-30
**App ID:** `quest`
**Status:** Design approved, plan pending
**Follows:** [M1](2026-07-29-quest-m1-design.md), [M1.1](2026-07-29-quest-m1-1-design.md), [M2](2026-07-29-quest-m2-design.md), [M3](2026-07-30-quest-m3-design.md), shipped at `fb9d9a0` (238 tests / 29 suites)

## Purpose

Quest has stored links since M1 and never been able to open one. Clicking a folder link
does nothing.

The cross-app spike (`docs/findings/2026-07-30-cross-app-resolution.md`) recommends `repo`
links opening Git Mage as the first real slice — but that requires a shared payload type in
`AinkradAppKit`, a receiver in Git Mage, and a **host-side fix so a launch focuses an
existing pane instead of spawning another**. That is work in the host repo, which the owner
is actively using, and it hinges on a decision only the owner can make (whether
"always a new pane" was intended).

So M4 takes the **zeroth slice** the spike identified: three of the seven link schemes need
no SDK change, no host change, and no pane semantics at all, because `NSWorkspace` handles
them in-process. It also puts the resolver layer in place that the Git Mage slice will plug
into later.

## Scope

| In | Out |
|---|---|
| `.url` opens in the default browser | Anything touching `AinkradAppKit` |
| `.folder` opens in Finder | Anything touching the Ainkrad host |
| `.file` is revealed in Finder | Git Mage / Lore / Leyline launch paths |
| `.repo`/`.branch`/`.pr`/`.commit`/`.unknown` are inert, and say why | Pane focus semantics |

## The sandbox trade, stated up front

M3 removed per-attachment security-scoped bookmarks because nothing read a link's path — the
writes were unreachable and accumulated. **This resolver is that reader**, so the decision is
worth restating rather than quietly reversing.

Chosen: **open via `NSWorkspace` with no scoped access.** It works today because the host
carries no `com.apple.security.app-sandbox` entitlement (verified: `Ainkrad/config/Ainkrad.entitlements`
holds only `com.apple.security.cs.disable-library-validation`).

Rejected: reintroducing per-attachment bookmarks now. The mechanism that would make them
necessary is a sandbox that does not exist, and M3's lesson was precisely that writing
bookmarks nothing reads is worse than not writing them. Also rejected: resolving through a
granted root when the link sits under one and falling back otherwise — that produces two
classes of link behaving differently for reasons invisible in the UI.

**The cost, documented in code at the opener:** if Ainkrad adopts `app-sandbox`, opening
files and folders outside a granted root will fail, and per-attachment bookmarks return —
with this resolver as the reader that justifies them.

## Architecture

### 1. `LinkResolution` — pure

`LinkResolution.route(for: Link) -> Route`, where:

```
Route = .reveal(URL) | .openFolder(URL) | .web(URL) | .inert(reason: String)
```

A pure switch on `scheme` plus URL construction. No `NSWorkspace`, no host, no SwiftUI, so
every mapping and every rejection is unit-testable.

Per scheme:

- `.url` → `.web`, **only** for a valid `http`/`https` URL. `LinkEditor` lets a user type
  anything into the identifier field, so a `.url` link can hold arbitrary text; handing that
  to the system opener is how an unexpected app launches. Anything else is `.inert`.
- `.folder` → `.openFolder`, only for an absolute path.
- `.file` → `.reveal` (selected in Finder), only for an absolute path. **Reveal, not open**:
  in a tool whose links are references rather than documents, the usual intent is to find the
  thing, not launch whatever owns the extension. Lore sets the same precedent with
  `activateFileViewerSelecting`.
- `.repo`, `.branch`, `.pr`, `.commit` → `.inert`, with a reason naming Git Mage as their
  future home. Half-working (opening a repo's folder instead of the repo) would be worse than
  honestly inert.
- `.unknown` → `.inert`. Visible but does nothing, as since M1.

### 2. `LinkOpener` — the side-effecting edge, behind a protocol

Three methods: `reveal(_:)`, `openFolder(_:)`, `openWeb(_:)`. The production conformance
wraps `NSWorkspace`. Tests use a recording double, so the whole click path is exercised
without touching the real Finder — and CI never opens a window.

### 3. Existence check before opening

A path can be deleted or a volume unmounted after a link was made. The production opener
checks existence first and reports "that folder no longer exists at \<path\>" rather than
silently doing nothing. Surfaced inline in `LinkListView`'s existing per-row error slot.

### 4. UI

`LinkListView` rows become clickable where the route is actionable; inert schemes render as
today and state their reason when clicked. `OverviewSurface` and `ItemEditor` both use
`LinkListView`, so project links and item links become clickable together with no
per-surface work.

## Testing

- **`LinkResolution`** carries the weight: every scheme's route, non-absolute paths refused,
  non-`http(s)` URL identifiers refused, inert schemes carrying a non-empty reason.
- **Opener double:** the click path calls the right method with the right URL; a missing
  target reports rather than silently no-oping.
- No GUI verification is possible here; the real Finder and browser behavior must be
  exercised in the Dev Host (`com.ainkrad.devhost`). The main host (`com.ainkrad.app`) is
  off-limits.

## Risk

Low, and deliberately so. The pure resolver is fully testable; the only untestable part is
`NSWorkspace` itself, isolated behind a one-purpose protocol. Nothing in this milestone
touches the store, the scheme machinery, the MCP surface, or any shipped invariant.
