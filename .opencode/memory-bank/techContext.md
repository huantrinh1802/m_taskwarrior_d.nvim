# Tech Context: m_taskwarrior_d.nvim

## Technologies
- **Language:** Lua (Neovim plugin)
- **Runtime:** Neovim 0.9+ (uses `vim.system`, `vim.api`, `vim.fn`, `vim.tbl_*`)
- **Task Backend:** Taskwarrior (pre-3.0 recommended)
- **UI Dependency:** `nui.nvim` for popups, inputs, menus, splits

## Build/Test Setup
- No formal test runner detected
- `lua/test.lua` is a manual scratch script
- `lua/test.json` contains sample Taskwarrior export data
- `lua/tests/test.md` is a sample Markdown file

## Key APIs Used
- `vim.system(args, { text = true }):wait()` — synchronous process spawn
- `vim.fn.json_decode(result)` / `vim.json.decode(content)` — JSON parsing
- `vim.api.nvim_buf_get_lines` / `vim.api.nvim_buf_set_lines` — buffer IO
- `vim.api.nvim_buf_set_extmark` — virtual text for due/scheduled dates
- `vim.fn.matchadd` — conceal Taskwarrior IDs and query markers

## Performance-Critical Code Paths
1. `utils.lua:render_virtual_due_dates()` — renders virtual due text; currently O(n) `task` processes
2. `init.lua:sync_tasks()` — syncs all checkboxes; O(n) lookups
3. `utils.lua:apply_context_data()` — applies query context; O(n) `task mod` processes
4. `utils.lua:update_related_tasks_statuses()` — dependency propagation; multiple process calls
