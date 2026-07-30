# Quest — M3 Design (Finish the Promises)

**Date:** 2026-07-30
**App ID:** `quest`
**Status:** Design approved, plan pending
**Follows:** [M1](2026-07-29-quest-m1-design.md), [M1.1](2026-07-29-quest-m1-1-design.md), [M2](2026-07-29-quest-m2-design.md), shipped at `fc91161` (196 tests / 25 suites)

## Purpose

Two kinds of work: the one real correctness gap M2's review left open, and the last three
promises from the M1 spec that were never built. Plus one investigation whose output is a
decision rather than code.

After M3, the spec and the app finally agree — three milestones of documentation have had
to hedge about things that were described but not shipped.

## Scope

| In | Out |
|---|---|
| Stale-plan detection for scheme edits | Cross-app link resolution itself (this milestone only investigates it) |
| List inline edit | Scheme templates, sharing a scheme between projects |
| Board grouping by epic | Anything the spike recommends — that is M4's decision |
| Project-creation auto-attach (repo + vault folders) | |
| A written spike finding on cross-app resolution | |

## 1. Stale-plan detection

**The gap.** `ProjectStore.applyScheme` overwrites the scheme with `plan.proposed` without
checking that the scheme the plan was diffed against still holds. M2's final review found
that an agent scheme edit made during the UI's confirm gap is silently reverted whenever it
leaves no item dangling — the pre-commit sweep catches orphaned items, not lost edits.

**The fix.** `SchemePlan.Plan` gains `current`: the scheme it was diffed against.
`applyScheme` compares the live document's scheme against `plan.current` and throws
`QuestError.schemeChangedUnderneath` before touching anything if they differ.

Value comparison rather than a revision counter: `StatusScheme` is already `Equatable`, it
needs no new persisted field and no lenient-decode migration, and it detects exactly the
thing that matters — "did what I diffed against change?" A document-wide revision counter
would additionally refuse a scheme plan because an unrelated task was created, which is a
false positive. The one case value comparison cannot see is a change leaving the scheme
byte-identical, which by definition changed nothing about the scheme.

**Recovery, not just refusal.** A refusal that dead-ends is a worse experience than the
silent revert it replaces:

- **UI:** catch the error, re-read the stored scheme, re-seed the editor rows, clear the
  pending plan, and say the scheme changed underneath — the user re-reviews against
  current reality.
- **MCP:** return a message telling the agent the scheme changed since it read it, and to
  re-read the project and re-submit.

## 2. List inline edit

The M1 spec promised "filterable, sortable, hierarchical, inline edit"; `ListSurface` ships
a modal sheet for every change. Rows gain an editable title field and a status picker,
committing through `store.updateItem` / `store.setStatus`. The sheet stays for everything
that does not belong in a row — body, dates, type, links. Per-row failures surface inline.

## 3. Board grouping by epic

The M1 spec promised "optional grouping by epic". `BoardGrouping` gains a grouped variant
returning, per epic, that epic's columns; `BoardSurface` gets a toggle. Pure logic, tested
like the rest of `Logic/`.

## 4. Project-creation auto-attach

The M1 spec promised that creating a project "offers to auto-attach matching repo and vault
folders, editable after".

**The sandbox constraint is real.** Ainkrad plugins cannot read arbitrary paths; Lore
reaches the vault through a security-scoped bookmark stored in `host.documents`
(`VaultBookmark`), resolved with `startAccessingSecurityScopedResource`. Quest cannot
silently scan `~/Home/Projects/Ainkrad/<Name>`.

**Both mechanisms ship, because they answer different needs:**

- **Root grants (the suggestion path).** In settings, the user grants a projects root and a
  vault root once, each stored as a security-scoped bookmark. With a root granted, creating
  a project scans one level for a name match and offers the matches as attachments —
  editable, never silent, never authoritative.
- **Per-folder picker (the escape hatch).** "Attach folder…" opens a picker for anything
  outside a granted root, storing a bookmark for that attachment. Always available, no
  grant required.

Name matching is deliberately dumb: a case-insensitive match on the project name against
one level of directory entries, offered as a suggestion. No fuzzy matching — a wrong
suggestion silently accepted is worse than no suggestion.

Attachments become ordinary `Link`s (`folder` scheme, or `repo` when the directory contains
a `.git`), so everything downstream already works.

## 5. Cross-app link resolution — spike only

M2 deferred this because most of the work lives outside Quest. M3 investigates rather than
builds. Read-only pass over the host and Git Mage / Lore / Leyline to answer:

- How could an app expose a resolvable resource, and does the host already have any
  mechanism (`PluginAppLauncher` / `AgentActionProvider`) that could route an open request?
- What would each app have to implement to resolve `repo`, `file`, and host links?
- What is the smallest useful slice — e.g. Quest asking the host to open Git Mage at a repo
  path — and what does it cost?

Output is a written finding with a recommendation, committed as a document. **No production
code changes.** Deciding what to build from it is M4's business.

## Testing

- Stale-plan detection: a plan applied after the stored scheme changed must throw and write
  nothing; the same plan against an unchanged scheme must still apply; MCP returns the
  re-read instruction.
- Inline edit: the pure part (what a row commit produces) tested directly; failures surface.
- Board grouping by epic: pure, including items whose epic is filtered out and epics with
  no children.
- Auto-attach: name matching is pure and tested (case-insensitivity, no match, several
  matches); bookmark storage and resolution tested against a temporary directory.

No GUI verification is possible in this environment; live-UI behavior must be exercised in
the Dev Host (`com.ainkrad.devhost`). The main host (`com.ainkrad.app`) is off-limits.

## Risk

Item 1 touches the scheme-editing path M2 reviewed twice — its tests must pin both the
refusal and the still-works case. Item 4 introduces the first filesystem access in Quest,
so the bookmark lifecycle (save, resolve, stale, access release) needs to follow Lore's
proven pattern rather than a new invention.
