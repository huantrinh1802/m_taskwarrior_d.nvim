# System Patterns: m_taskwarrior_d.nvim

## Module Layout
- `init.lua`: config, command registration, autocmds, orchestration (`sync_tasks`, ...)
- `task.lua`: the only module that calls the `task` CLI (`execute_task_args`, `get_task_by`, `get_tasks_bulk[_sync]`, `uuid_or_filter`, `chunk_list`)
- `utils.lua`: parsing, sync algorithm, dependency propagation, query rendering, due-date virtual text, conceal provider
- `ui.lua`: `nui.nvim` popups and inputs
- `health.lua`: `:checkhealth`

## Key Patterns

### Batched CLI access
- UUID filters are built as separate argv tokens (`uuid:a`, `or`, `uuid:b`); never concatenate them into one string, because `vim.system` bypasses the shell.
- Exports: 100 UUIDs per chunk; mods: 50 per chunk with `rc.bulk=0`.
- `vim.system` callbacks run in a fast-event context: use `vim.json.decode`, not `vim.fn.*`, and `vim.schedule` before touching buffers.

### Sync
- `sync_tasks`: first pass collects checkbox lines + UUIDs; one batched export builds `task_cache`; second pass re-reads each line (a parent may have written `$id{}` onto it) and calls `sync_task(line, n, task_cache, synced)`.
- `synced` (set of line numbers) ensures each line goes through `add_or_sync_task` once; already-synced lines are only read for their uuid, but still get their own `check_dependencies`.

### Due-date rendering
- Per-buffer `due_state { gen, claims }`: each render bumps `gen` and claims the uuids it requested; only the newest claimer draws a uuid's mark. Whole-buffer renders reset claims.
- Taskwarrior dates are UTC; `parse_ISO8601_date` converts using the local offset at that instant.

### Conceal
- One decoration provider (`ns conceal`) sets ephemeral extmarks over the visible rows on every redraw for buffers in `utils.conceal_buffers` (enabled on BufEnter, removed on BufWipeout).

### Highlights
- Plugin-owned groups with `default = true` (`TWConceal`, `TWDueDate`, `TWDueSoon`, `TWDueOverdue`), set in `setup()` and on `ColorScheme`. Never redefine global groups like `Conceal`.
