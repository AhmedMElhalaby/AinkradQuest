# Quest — M2 Design (Status Scheme Editing)

**Date:** 2026-07-29
**App ID:** `quest`
**Status:** Design approved, plan pending
**Follows:** [M1](2026-07-29-quest-m1-design.md) and [M1.1](2026-07-29-quest-m1-1-design.md), shipped at `4cf1aa4` (148 tests / 21 suites)

## Purpose

Per-project status schemes were a headline feature of Quest's original design: board
columns and completion both derive from them, so they are the one place a project's
workflow is defined. They have never been editable. Every project runs the built-in
default for its kind, and the shipped docs say so because a review caught them
overclaiming otherwise.

M2 makes schemes editable, in the UI and over MCP, and closes the last outstanding
promise from the M1 spec: the `update_status_scheme` tool.

## Scope

| In | Out |
|---|---|
| Editing a project's statuses: add, rename, recolour, reorder, recategorise, remove | Cross-app link resolution (Git Mage / Lore / Leyline) — needs a host mechanism that does not exist yet |
| Reassigning items off a removed status | Scheme templates or sharing a scheme between projects |
| `update_status_scheme` MCP tool | List inline edit, board grouping by epic, project-creation auto-attach |

Cross-app link resolution was considered for M2 and deferred deliberately: most of that
work lives in the host and in three other repos, not in Quest, and it should start with a
spike on how apps expose resolvable resources.

## The governing invariant

**Every item's status id exists in its project's scheme.** The store already enforces
this on write — `createItem` and `updateItem` reject an unknown status — and boards and
completion rely on it. Scheme editing is the first operation that could break it, so
every decision below protects it.

The defensive tolerance elsewhere (`BoardGrouping` drops items with unknown statuses,
`isDone` returns false) stays as a backstop, but must never become the normal path: an
item that exists in the list and silently vanishes from the board is the invisible-orphan
class this project has already fixed twice.

## Decisions

### Removing a status reassigns its items

Deleting a status that holds items requires choosing a destination. The editor shows the
count ("In Review — 4 items") and will not proceed without one. Items are never left
pointing at a status that no longer exists.

Rejected: blocking deletion until the column is empty by hand (busywork), and allowing
items to dangle (creates data the store itself would refuse to accept on write).

### `id` is immutable; everything else is editable

`Status` is `{ id, name, category, colorToken }`. Items store the `id`, so:

- **Rename** changes display text only and touches no item.
- **Recolour** and **reorder** touch no item; order is board column order.
- **Recategorise** IS allowed and is retroactive: moving a status into `.done` stamps
  `closedAt` on every item in it, and moving it out clears `closedAt`. The count is shown
  before confirming, and the change is logged.
- **Changing an `id`** is refused. It is a bulk item rewrite disguised as a rename, and
  `id` is the stable handle items, the activity log, and the agent all rely on.

## Architecture

### 1. `SchemePlan` — pure, and where the weight sits

`SchemePlan.plan(current:proposed:reassignments:items:)` returns either a validation
failure or a plan describing exactly what will happen: statuses added, renamed,
recoloured, reordered, recategorised (with the items whose `closedAt` will change), and
removed (with the items being reassigned and their destinations).

Both the UI and the MCP tool call this, so "what does this change do to my items" has one
definition, and the preview the user confirms is literally the plan that executes.

Validation rejects:

- an empty scheme
- a scheme with no `.done` status — completion would become unreachable
- duplicate status ids
- a removal that has items but no destination
- a destination that is not present in the **proposed** scheme
- any change to an existing status's `id`

### 2. `ProjectStore.applyScheme(_:to:actor:)` — atomic

Executes an already-validated plan against one project document: rewrite the scheme,
reassign items off removed statuses, restamp `closedAt` where categories changed, append
**one** `ActivityEvent` of kind `schemeUpdated`, then `commit`. Either the whole plan
applies or nothing is touched — no partial scheme edits.

`ActivityKind.schemeUpdated` returns. It has been declared twice before and deleted both
times for having no emitter; this is the milestone that makes it real.

### 3. UI — in the project settings sheet

M1.1 added that sheet and deliberately left room for this. Reorderable status rows with
name, colour, and category; add and remove; removing a status with items opens a
reassignment picker showing the count. A confirm step states the plan in words before
applying. Failures surface inline.

### 4. MCP — one tool, whole-scheme submission

`update_status_scheme` takes `projectID`, the full ordered status list, and an optional
reassignment map. It plans first: on validation failure it returns the reason and mutates
nothing; on success it applies and reports exactly what it did ("removed In Review, moved
4 items to Todo").

Whole-scheme rather than granular `add_status`/`remove_status` tools: it is what the M1
spec named, it keeps the tool surface at fifteen rather than eighteen, and a single
submission is atomic where a multi-call sequence can fail halfway and leave a half-edited
scheme.

**Classified `destructive: true`**, with the reasoning written into `QuestMCPServer`'s
classification comment as that file requires: unlike other mutations, this one can
reassign and restamp many items at once, and the agent cannot judge what a workflow
column was for.

### 5. Docs

README and `docs/catalog-entry.json` currently state that schemes are not editable in
v0.1.0. That statement was added after a review caught the copy overclaiming; it must be
corrected in the same milestone that makes it false.

## Testing

- **`SchemePlan`** carries the weight: every validation rejection, every change kind,
  category-change restamping in both directions, reassignment correctness, and behavior
  with soft-deleted items present.
- **Store:** atomicity (a failed apply leaves the document untouched), exactly one
  activity event, and persistence across a relaunch.
- **MCP:** destructive classification, no mutation on invalid input, result text an
  assistant can act on, and refusal on a trashed project.

## Risk

This is the first feature that rewrites existing items in bulk. The mitigation is
structural: planning is pure and separate from applying, so the dangerous logic is fully
testable without a store, and the same plan the user confirms is the one that runs.

No GUI verification is possible in this environment; live-UI behavior must be exercised in
the Dev Host (`com.ainkrad.devhost`).
