# Tech Context: m_taskwarrior_d.nvim

## Technologies
- **Language:** Lua (Neovim plugin)
- **Runtime:** Neovim 0.10+ (`vim.system`, `vim.json`, decoration providers; checked by `:checkhealth`)
- **Task Backend:** Taskwarrior. README says pre-3.0; regression suites also pass against 3.5.0 (the version installed locally), and checkhealth warns on 3.x.
- **UI Dependency:** `nui.nvim`

## Build/Test Setup
- No build system or package manager.
- Syntax check: `luajit -b lua/m_taskwarrior_d/<file>.lua /dev/null`
- Regression tests: `nvim --headless -u NONE -c "lua dofile('lua/tests/test_task_batch.lua')"` and the same for `test_sync_render.lua`. They use a throwaway `TASKRC`/`TASKDATA` and need the real `task` binary.
- `lua/test.lua`, `lua/test.json`, `lua/tests/test.md` are untracked scratch files.
- Lint: `luacheck lua` (config in `.luacheckrc`; pre-existing warnings in `init.lua`/`utils.lua` are ignored by code — drop a code once fixed). Locally, install with `luarocks --lua-version 5.1 --lua-dir $(brew --prefix luajit) install --local luacheck` (the Lua 5.5 build of luacheck crashes).
- CI: `.github/workflows/ci.yml` runs luacheck and both regression suites on push to `main` and on PRs, against Neovim v0.10.4 and stable with Ubuntu's apt Taskwarrior (2.6.x).

## Key APIs Used
- `vim.system(args, { text = true })` sync (`:wait()`) and async (callback)
- `vim.json.decode` (safe in fast-event callbacks); `vim.fn.json_decode` in older sync paths
- `nvim_buf_set_extmark` (due virtual text; ephemeral conceal extmarks), `nvim_set_decoration_provider`
- `nvim_set_hl(..., { default = true })` for highlights
