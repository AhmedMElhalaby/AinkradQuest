# Quest — M1.1 Design (Links, Project State, Timeline Spanning)

**Date:** 2026-07-29
**App ID:** `quest`
**Status:** Design approved, plan pending
**Follows:** [M1](2026-07-29-quest-m1-design.md), shipped at commit `7683373` (104 tests / 18 suites)

## Purpose

M1 shipped Quest's spine: projects, three-level work items, per-project status
schemes, five surfaces, soft delete with trash, and a 12-tool MCP surface. The final
whole-branch review found several promises in the M1 spec that were never carried into
the M1 plan, plus gaps that only became visible once the app existed.

M1.1 closes the three that affect daily use. It is deliberately small and additive.

## Scope

| In | Out (deferred to M2) |
|---|---|
| Links on projects **and** items, add and remove, in the UI and over MCP | Status-scheme editing (and its `update_status_scheme` MCP tool) |
| Project state: pause, archive, trash, restore, and a settings sheet | Cross-app link resolution (Git Mage / Lore / Leyline) |
| Timeline epics spanning their children | List inline edit, board grouping by epic, project-creation auto-attach |

### Why the status-scheme editor is deferred

Editing a scheme raises a real design question, not an implementation detail: what
happens to items whose status is deleted or renamed. That decision touches board
grouping, completion rollups, and every persisted project document, and it deserves its
own milestone. Until then the shipped docs stay honest — they state that schemes come
from the project's kind at creation and are not editable.

## 1. Links

`Link`, `LinkScheme`, and `LinkValidation` ship in M1 and need no change. Repo-scoped
schemes (`branch`, `pr`, `commit`) already require a repo, because a project routinely
has many.

**What links can attach to.** Both `Project` and `WorkItem` already carry `links`, but
M1 only edits project links and the agent cannot touch either. M1.1 makes both editable
from both surfaces. Item-level links are where the daily value is: an item pointing at
its branch and its PR is what makes Quest a hub rather than a list.

**One mutation path.** A `LinkTarget` enum (`.project(UUID)` / `.item(UUID)`) lets the
store expose a single pair of methods:

- `ProjectStore.addLink(to: LinkTarget, link: Link, actor: ActivityActor) throws`
- `ProjectStore.removeLink(from: LinkTarget, link: Link, actor: ActivityActor) throws`

One path rather than four means validation, activity logging, and trashed-target
refusal cannot diverge between projects and items.

**Activity.** `linkAdded` and `linkRemoved` are restored to `ActivityKind` and genuinely
emitted. They were deleted in M1's final fix wave precisely because nothing emitted them.

**UI.** `LinkEditor` becomes target-aware rather than project-only, and `ItemEditor`
gains a links section reusing it. Existing Overview behavior must not regress.

**MCP.** Two new tools, both mutating and **not** destructive, consistent with M1's
classification (creates and updates are ungated; only deletes are gated):

- `add_link` — takes `projectID` **or** `itemID`, plus `scheme`, `identifier`, `label`,
  and `repo`.
- `remove_link` — same target shape, plus enough to identify the link.

Both refuse trashed targets, matching the guards added at the end of M1, and both run
the shared `LinkValidation` rather than reimplementing the repo rule.

## 2. Project state

M1 left `paused` and `archived` reachable only from tests and the agent: the sidebar
lists `activeProjects` only, so a paused project simply disappears, and there is no UI
to pause, archive, trash, or rename a project at all.

- **Context menu** on a sidebar project: Pause, Archive, Move to Trash, Restore.
- **Filter control** switching the list between Active / Paused / Archived / All, so no
  state is unreachable.
- **Settings sheet** for name, summary, icon, and colour. Overview cannot rename a
  project today even though the agent's `update_project` can.
- **Store:** `setState(_:state:actor:)` so pause is reachable (only `archiveProject`
  exists), and state-filtered accessors alongside `activeProjects`. Trash and restore
  already exist and are reused unchanged.

## 3. Timeline epic spanning

The M1 spec promised "epics as bars spanning their children"; the shipped
`TimelineLayout` uses each item's own dates, so an undated epic falls to the unscheduled
rail even when every child is scheduled.

Rule, in precedence order:

1. An epic with its own `startDate`/`dueDate` keeps them.
2. An epic with no dates of its own, whose **live** descendants have dates, renders as a
   derived bar from the earliest descendant start to the latest descendant end.
3. An epic with neither stays in the unscheduled rail.

Pure logic inside `TimelineLayout`, which already has a test suite. Soft-deleted
descendants are excluded from the derivation, consistent with every other rollup.

## Risks

The `LinkTarget` refactor touches shipped code — `LinkEditor` and its Overview wiring —
and is the one place this milestone can regress working behavior. It gets its own task,
with tests covering both targets before the UI changes.

Everything else is additive: new store methods, new views, new MCP tools, and one pure
function extended.

## Testing

- Store: link add/remove on both targets, including trashed-target refusal and activity
  emission; every project state transition.
- MCP: both new tools, including target validation, the shared repo rule, and refusal on
  trashed targets.
- Logic: epic spanning across all three precedence cases, with deleted descendants
  excluded.
- No GUI verification is possible in this environment; live-UI behavior stays unverified
  by design and must be exercised in the Dev Host (`com.ainkrad.devhost`).
