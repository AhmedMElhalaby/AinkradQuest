# Quest

Projects, epics, work items and subtasks for Ainkrad — a task/quest tracker plugin with
five surfaces (Today, Overview, List, Board, Timeline), soft delete with restore, and a
full-control MCP surface so the assistant can file and move real work instead of writing
markdown about it.

## Model

- **Three levels, capped.** A project holds epics; an epic holds items (task, bug, story,
  chore, spike); an item holds subtasks. Only epics may sit at the project's top level —
  `HierarchyRules` refuses a move that would exceed three levels or place an item under
  its own descendant.
- **Per-project status schemes.** Each project owns its own `StatusScheme` — the board
  columns are project-specific, not global. `kind: "software"` gets
  Backlog/Todo/In Progress/In Review/Done; `kind: "general"` gets the same without
  In Review. Completion follows a status's `done` category, not its name or label text.
- **Links.** Projects and items carry a typed `Link` list — `file`, `folder`, `url`,
  `repo`, `branch`, `pr`, `commit` (unknown schemes decode to `.unknown` rather than being
  dropped, so a link written by a future version still displays). Repo-scoped links
  (`branch`, `pr`, `commit`) always carry which repo they belong to, because a project with
  several repos can't otherwise disambiguate "main". Multi-repo projects are the normal
  case, not an edge case.
- **Soft delete.** Deleting a project or item marks it trashed (`isTrashed` /
  `deletedAt`) rather than erasing it. Trashed items disappear from every board and list
  but are restorable from the Trash surface; deleting an item also trashes its
  descendants.

## The five surfaces

| Surface | File | What it's for |
|---|---|---|
| Today | `TodaySurface.swift` | Cross-project inbox: what's due or overdue today, plus quick capture. |
| Overview | `OverviewSurface.swift` | One project's summary — links, activity, epic progress. |
| List | `ListSurface.swift` | Filterable, sortable flat list of items. |
| Board | `BoardSurface.swift` | Drag-and-drop columns from the project's status scheme. Epics are containers, not board cards — every level below the epic is board-visible. |
| Timeline | `TimelineSurface.swift` | Scheduled items laid out over time, with an unscheduled rail so anything without dates isn't lost. |

Quick capture files into an auto-created "Inbox" epic rather than directly under the
project, since only epics may sit at the top level.

## MCP tools

Quest publishes twelve tools over MCP (`QuestMCPServer.swift`), following the same
declarative-table shape as Ainkrad's other plugin MCP servers. `update_status_scheme`
does **not** exist — an earlier design mentioned it, but `QuestMCPOperations` has no
operation to route it to, so it was deliberately left out rather than invented.

| Tool | destructive | readOnly | Why |
|---|---|---|---|
| `list_projects` | | ✓ | Reads the in-memory store. |
| `get_project` | | ✓ | Reads the in-memory store. |
| `search_items` | | ✓ | Reads the in-memory store. |
| `get_item` | | ✓ | Reads the in-memory store. |
| `create_project` | | | Filing work is the point of the app — gating every create behind approval would make Quest require a click for its whole reason to exist. |
| `update_project` | | | Same reasoning; also fully editable/reversible afterwards. |
| `create_item` | | | Same. Every agent write is logged with `actor: .agent`. |
| `update_item` | | | Same. |
| `move_item` | | | Same; refused outright (not just gated) if it would violate the hierarchy. |
| `set_status` | | | Same. |
| `delete_item` | ✓ | | Soft and restorable, but removing an item from every surface is disruptive enough — and the agent can't judge what a stale-looking item was for — that a person should agree first. |
| `delete_project` | ✓ | | Same reasoning at project scope: removes a project and all of its work from every surface. |

`destructive` is what the host's Full-auto guard gates on; `requiresLiveApp` is false on
every tool, since the store loads from `host.documents` and works whether or not a Quest
window is open — which is what lets the assistant file a task while you're in a terminal.

## Building and running

```
xcodegen generate
xcodebuild -scheme QuestPlugin -configuration Debug -derivedDataPath build -destination 'platform=macOS' build
```

or just `make build`.

### Sideloading

```
make sideload
```

This targets the **dev host** (`com.ainkrad.devhost`), not the main Ainkrad app
(`com.ainkrad.app`) — it copies the built bundle into the dev host's `DevPlugins`
directory so you can iterate without touching your real workspace. `make test` runs the
test suite the same way.

### Releasing

`scripts/release.sh vX.Y.Z` does a clean Release build, packages
`dist/quest.bundle.zip`, reads `AinkradAPIVersion` from the *built* bundle's Info.plist
(never hardcoded — it's stamped by `scripts/stamp-api-version.sh` from whichever
AinkradAppKit revision the build actually linked against), and publishes a GitHub release
with `gh release create`.
