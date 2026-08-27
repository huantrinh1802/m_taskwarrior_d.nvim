# System Patterns: m_taskwarrior_d.nvim

## Module Layout
- `lua/m_taskwarrior_d/init.lua`: main module, command registration, autocmds, high-level orchestration
- `lua/m_taskwarrior_d/task.lua`: Taskwarrior CLI wrapper (`execute_task_args`, `get_task_by`, `add_task`, `modify_task`, etc.)
- `lua/m_taskwarrior_d/utils.lua`: buffer/line utilities, parsing, task sync logic, virtual due-date rendering
- `lua/m_taskwarrior_d/ui.lua`: `nui.nvim` popups and inputs

## Key Patterns

### Synchronous CLI Execution
`task.lua` uses `vim.system(...):wait()` for all Taskwarrior calls. This blocks the editor until the process returns.

### Per-Task Process Spawning
- `render_virtual_due_dates` collects UUIDs then calls `get_task_data_async`, which is a **placeholder** that still loops over UUIDs calling `get_task_by` once per task.
- `sync_tasks` calls `sync_task` per checkbox line, which calls `add_or_sync_task` → `get_task_by` per existing UUID.
- `apply_context_data` runs `task <uuid> mod <query>` once per task under a query header.

### Autocmd-Driven Workflow
`setup()` registers `BufEnter` and `BufWritePre` autocmds for Markdown files. The README example recommends running `TWBufQueryTasks` and `TWSyncTasks` on these events, which compounds the slowness.

### Concealment
Taskwarrior IDs and query markers are concealed using `vim.fn.matchadd` with `Conceal` highlight.

### Virtual Text Namespace
`utils.lua` creates a namespace `due` and uses `nvim_buf_set_extmark` with `virt_text_pos = "eol"` for due/scheduled text.
