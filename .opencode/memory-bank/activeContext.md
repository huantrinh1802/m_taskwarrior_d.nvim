# Active Context: m_taskwarrior_d.nvim

## Current Focus
Performance fixes for due/scheduled rendering and full-buffer sync have been implemented and validated. The changes are on branch `fix/performance-batch-taskwarrior-calls` and are ready for review/commit.

## What Was Done
1. **Real async batched export** — added `task.get_tasks_bulk` (async) and `task.get_tasks_bulk_sync` (blocking wrapper). UUIDs are chunked in groups of 100 and queried with `task uuid1 or uuid2 ... export`, reducing N processes to ~N/100.
2. **Fixed `utils.render_virtual_due_dates`** — replaced the blocking placeholder with the batched export, used `vim.schedule` to set extmarks on the main thread, and kept the existing filter that skips deleted/completed tasks.
3. **Optimized `init.sync_tasks`** — first pass collects UUIDs, second pass syncs each line using a cached task map, eliminating one `task export` call per existing task.
4. **Optimized `utils.apply_context_data`** — batched `task mod` calls into chunks of 50 UUIDs instead of one process per task.
5. **Updated `task.get_tasks_by`** — now reuses the bulk export.
6. **Fixed extmark/Conceal correctness** — defined the missing `DueOverdue` highlight, guarded async extmark updates with `nvim_buf_is_valid`, switched `conceallevel` to window-local, and delete old `matchadd` IDs before adding new ones to avoid duplicate conceal matches.

## Validation
- `luajit -b` syntax check passed for `task.lua`, `utils.lua`, and `init.lua`.
- Standalone Lua test: 250 UUIDs fetched in 3 chunked calls.
- Headless Neovim test: `render_virtual_due_dates` produced 2 extmarks for pending due/scheduled tasks and correctly skipped the completed task.

## Open Questions / Future Work
- Should `sync_tasks` become incremental (only sync changed lines) to avoid scanning the whole buffer? Out of scope for this fix but a natural next step.
- Should the chunk sizes (100 for export, 50 for modify) be configurable? Current values are conservative defaults.
