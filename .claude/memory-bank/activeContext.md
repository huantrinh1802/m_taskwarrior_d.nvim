# Active Context: m_taskwarrior_d.nvim

## Current Focus
Branch `fix/performance-batch-taskwarrior-calls`: batching Taskwarrior CLI calls plus the correctness fixes found while reviewing it. All review items are fixed except one (see Open Questions). Ready for final review / merge to `main`.

## Recent Changes (review follow-ups, 2026-10-23)
- `parse_ISO8601_date` now treats Taskwarrior's `...Z` timestamps as UTC (was read as local time, so due text was off by the UTC offset). DST handled per date.
- `health.lua` no longer crashes on a `task --version` that doesn't start with a digit.
- `task.get_tasks_bulk_sync` warns via `vim.notify` when the 5s `vim.wait` times out (sync then falls back to per-task `get_task_by`).
- `sync_tasks` threads a `synced` line-number set through `sync_task`/`check_dependencies`, so each nested line is passed through `add_or_sync_task` once (a 3-level list went from 6 calls to 3). Callers without the set keep the old behavior.
- Highlights are plugin-owned `default = true` groups: `TWConceal`, `TWDueDate`, `TWDueSoon` (orange), `TWDueOverdue` (red), set once in `setup()` and re-applied on `ColorScheme`. The global `Conceal` group is no longer touched.
- `due_state.claims` is reset on whole-buffer renders so it no longer grows without bound.
- Memory bank moved from `.opencode/memory-bank/` to `.claude/memory-bank/`.

## Open Questions / Future Work
- **Parallel export chunks (deliberately not changed):** `get_tasks_bulk` starts one `task` process per 100-UUID chunk at once. Fine on TW 3.x (SQLite); on 2.x a read can run gc/recurrence and contend for the data-file lock. Options: run chunks one after another, or add `rc.gc=off rc.recurrence=off` to exports.
- Should `sync_tasks` become incremental (only sync changed lines)?
- Should chunk sizes (100 export / 50 modify) be configurable?
