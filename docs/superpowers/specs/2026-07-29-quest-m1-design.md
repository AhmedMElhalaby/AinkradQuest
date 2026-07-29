# Quest — M1 Design (The Spine)

**Date:** 2026-07-29
**App ID:** `quest`
**Status:** Design approved, plan pending

## Purpose

Quest is the project-management app for Ainkrad. It replaces Jira, Linear, GitHub
Projects, GitHub Issues, and ad-hoc task lists as the single place where Ahmed tracks
everything he is working on — software and non-software alike — and it is the surface
the Ainkrad assistant uses to file, move, and query that work.

A "project" is anything being worked on. It may have many repos (Ainkrad has eleven;
Optimus has a frontend and a backend), or none at all.

## Positioning: own tasks, federate the rest

Quest owns the one thing no existing Ainkrad app owns: **work items**. Documents belong
to Lore and the vault, repos and PRs to Git Mage, SSH sessions to Leyline. Quest links
out to those rather than duplicating them, so it grows more useful as the other apps
improve instead of competing with them.

The store sits behind a `ProjectRepository` protocol from day one. A host-wide shared
Ainkrad content store is planned (M4); when it arrives it replaces the JSON
implementation and nothing above the protocol changes.

## Milestones

| Milestone | Scope |
|---|---|
| **M1 — Spine** (this spec) | Projects, three-level work items, typed statuses, links, five surfaces, full MCP surface, soft delete + activity log |
| M2 — Integrations | Live Git Mage binding (branch/PR from item), Lore note attach/create, Leyline host links, cross-app open resolver |
| M3 — Import & migration | One-shot importers from GitHub Issues / Jira / Linear; vault plan → epic+items ingestion |
| M4 — Shared store | Repoint `ProjectRepository` at the host-wide Ainkrad content store |

## Decisions taken (and what they rule out)

- **No external sync.** Quest is the source of truth. GitHub Issues goes unused. Issue
  and PR references are stored as inert links, never synchronized. Two-way sync only
  pays off with collaborators in the other system; there are none.
- **Hierarchy is capped at three levels**, not freely nested. Boards, rollups, and epic
  progress stay well-defined, and six-deep trees can't happen.
- **No Jira ceremony.** No workflow engine with transition guards, no permission
  schemes, no custom-field builder, no story points, no sprint machinery. Those are the
  reasons the tool being replaced was unpleasant.
- **No estimates in M1.** Add if missed.
- **The agent has full control**, including create and delete. Safety comes from
  reversibility (soft delete, activity log), not from withheld permissions.

## Data model

### Project
`id`, `name`, `summary`, `icon` (SF Symbol), `color`, `kind` (`software` | `general`),
`state` (`active` | `paused` | `archived`), `statusSchemeID`, `links: [Link]`,
`createdAt`, `archivedAt`.

### WorkItem
`id`, `projectID`, `parentID` (nil = epic), `type` (`epic` | `task` | `bug` | `story` |
`chore` | `spike`), `title`, `body` (markdown), `statusID`, `priority`, `labels: [String]`,
`startDate?`, `dueDate?`, `orderIndex`, `links: [Link]`, `createdAt`, `updatedAt`,
`closedAt?`, `deletedAt?`.

Depth is enforced in the store, not by convention: a `parentID` producing depth > 3 is
rejected with a typed error. `type == .epic` is legal only at depth 0, so the type and
the structural position cannot disagree. Every item below the epic is board-visible and
independently status-tracked — subtasks are real items, not checklist rows.

### StatusScheme
An ordered `[Status { id, name, category: todo | active | done, color }]`, owned per
project. Board columns and completion logic both derive from it, so progress has exactly
one source of truth.

Default scheme: **Backlog → Todo → In Progress → In Review → Done**.
`general` projects default to the same scheme without In Review.

### Link
`{ scheme, identifier, label }`. M1 resolves `file`, `folder`, `url`, `repo`, `branch`,
`pr`, `commit`. Unknown schemes are stored and displayed but not opened, so M2 adds
resolvers without a data migration — this is the shape that becomes a cross-app URI
registry later.

Repo-scoped links (`branch`, `pr`, `commit`) carry their repo identity. Multi-repo
projects are the normal case, not an exception.

On project creation Quest offers to auto-attach a matching repo folder and vault folder
by name. The suggestion is editable and never authoritative.

### ActivityEvent
Append-only, per project: what changed, which item, actor (`user` | `agent`), timestamp.
This is what makes agent full-control livable — a bad agent call is visible and undoable
rather than prevented.

## Persistence

One document per project (`project-<id>.json`) plus one index document holding project
summaries, all through `host.documents` in the house style. Today/Inbox reads the index
plus open projects rather than decoding every item ever written — the reason Quest does
not follow Leyline's single-document approach.

All access goes through `ProjectRepository`; the JSON implementation is the only thing
M4 replaces.

## Architecture

`Sources/QuestFeature/{Models,Store,Logic,Views,MCP}` plus a thin `QuestPlugin` entry
point with `Info.plist`, matching Lore, Leyline, and Git Mage.

- **Store** — `ProjectStore` (`@MainActor @Observable`), the single mutation point.
  Every write passes through it, so activity logging and persistence cannot be bypassed
  by a view or by an MCP call.
- **Logic** — pure functions, no UI or store dependency: filtering, sorting, epic
  progress rollup, board grouping, timeline lane packing, depth validation, the
  Today/Inbox query. The test weight lives here; purity is what makes that possible.
- **Views** — five surfaces over one store.
- **MCP** — declarative tool table delegating to the store.

## Surfaces

1. **Today / Inbox** — cross-project; active items, due and overdue, recently touched,
   quick capture into a default project. The app opens here, so it is useful before a
   project is chosen.
2. **Project overview** — summary, links, epic progress, recent activity.
3. **List** — filterable, sortable, hierarchical (epics expand), inline edit.
4. **Board** — columns from the project's status scheme, drag to change status,
   optional grouping by epic.
5. **Timeline** — epics as bars spanning their children, items placed by start/due date,
   and an **unscheduled rail** for dateless items so nothing silently disappears. The
   timeline is only as good as the dates maintained on items; `startDate` and `dueDate`
   are first-class for this reason.

Navigation is a project sidebar plus a surface switcher. No window per project — the
HUD already handles panes.

## MCP surface

Declarative tool table with per-tool classification, following `LoreMCPServer` /
`LeylineMCPServer`.

| Tool | Classification |
|---|---|
| `list_projects`, `get_project`, `search_items`, `get_item` | `readOnly: true` |
| `create_project`, `update_project`, `create_item`, `update_item`, `move_item`, `add_link` | mutating, not destructive |
| `delete_item`, `delete_project`, `update_status_scheme` | `destructive: true` |

Deletes are soft, so `destructive` here means disruptive-but-recoverable: the host's
Full-auto guard should still ask before an agent removes a project from view or rewrites
the status scheme every board column depends on. The reasoning is documented in the
server file, as the other apps do.

## Error handling

Store mutations return typed failures — depth violation, unknown status, missing parent,
illegal epic nesting — surfaced inline in the UI and as structured MCP errors.

Persistence failures never silently drop a write: the store keeps the in-memory change,
marks the document dirty, retries, and shows a persistent banner if it still cannot
write.

## Testing

- **Logic** — thorough unit coverage: rollups, depth rules, Today/Inbox queries, board
  grouping, timeline lane packing.
- **Store** — mutation and activity-log correctness against an in-memory
  `ProjectRepository`.
- **MCP** — tested at the operations layer, not through a live server.

## Open for later

Estimates, saved filters, recurring items, notifications, and timeline drag-to-schedule
are deliberately out of M1.
