# Progress: m_taskwarrior_d.nvim

## What Works
- Core plugin loads and registers commands/autocmds
- Checkbox detection and Taskwarrior sync
- Concealment of IDs/query markers
- Virtual text for due/scheduled dates (now batched and non-blocking)
- Query views and dependency rendering
- Floating UI for view/edit/run commands

## Recent Changes
- Replaced the fake-async `get_task_data_async` placeholder with a real batched export.
- Added `task.get_tasks_bulk` and `task.get_tasks_bulk_sync` to fetch many tasks in one (or chunked) `task ... export` call.
- Updated `utils.render_virtual_due_dates` to use the batched export and `vim.schedule` for extmark updates.
- Updated `init.sync_tasks` to collect all UUIDs up front, batch-export them once, and pass a task cache through `sync_task`/`add_or_sync_task`.
- Updated `utils.apply_context_data` to batch `task mod` calls into chunks of 50 UUIDs.
- Updated `task.get_tasks_by` to use the new bulk export.
- Fixed extmark/Conceal correctness: defined missing `DueOverdue` highlight, guarded async extmark updates against deleted buffers, made `conceallevel` window-local, and removed duplicate `matchadd` conceal matches on buffer re-entry.
- Replaced window-local `matchadd` conceal with buffer-local extmarks via `utils.render_conceal_marks()`, eliminating duplicate conceal matches when switching Markdown buffers.

## Validation
- LuaJIT syntax check passed for all modified modules.
- Standalone Lua test confirmed 250 UUIDs are fetched in 3 chunked Taskwarrior calls.
- Headless Neovim test confirmed `render_virtual_due_dates` sets the correct extmarks and filters completed tasks.

## Known Issues
- `sync_tasks` still calls `task add` and `task modify status` per task where required; these cannot be batched safely without deeper changes.
- No formal test suite exists in the repo; tests were run from a temporary directory.

## Next Steps
- Monitor real-world performance on large Markdown files.
- Consider making `sync_tasks` fully incremental (only sync changed lines) in a future pass.
