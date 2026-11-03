# Tech Context: m_taskwarrior_d.nvim

## Technologies
- **Language:** Lua (Neovim plugin)
- **Runtime:** Neovim 0.10+ (`vim.system`, `vim.json`, decoration providers; checked by `:checkhealth`)
- **Task Backend:** Taskwarrior. README says pre-3.0; regression suites also pass against 3.5.0 (the version installed locally), and checkhealth warns on 3.x.
- **UI Dependency:** `nui.nvim`

## Build/Test Setup
- No build system or package manager.
- Syntax check: `luajit -b lua/m_taskwarrior_d/<file>.lua /dev/null`
- Tests: `scripts/test.sh` runs every `lua/tests/test_*.lua` in its own headless Neovim (or pass suite paths). Suites use `lua/tests/helpers.lua` (isolated `TASKRC`/`TASKDATA`, stubs, print/notify capture) and need the real `task` binary; `test_commands`/`test_comment_markers` need nui.nvim (`$NUI_PATH`, else cloned into `.tests/`).
- Coverage: `eval "$(luarocks --lua-version 5.1 path)"; COVERAGE=1 COVERAGE_MIN=100 scripts/test.sh` (luacov for LuaJIT: `luarocks --lua-version 5.1 --lua-dir $(brew --prefix luajit) install --local luacov`). luacov only needs its Lua sources on `LUA_PATH` (CI clones v0.17.0); `includeuntestedfiles` was dropped because it needs the compiled `lfs`, and `scripts/test.sh` instead fails if a `lua/m_taskwarrior_d/*.lua` module is missing from the report. Line coverage is 100% across all six modules.
- LuaJIT credits the first line of a multi-line expression to a later line, so luacov reports such lines as missed even when they ran; keep expressions on one line (or name parts) rather than adding `luacov: disable`.
- nui.input does not take focus headlessly when mounted from a :command, so `test_commands` fakes it (`H.fake_nui_input`/`H.submit_input`); popups, menus and splits are real.
- `lua/test.lua`, `lua/test.json`, `lua/tests/test.md` are untracked scratch files.
- Lint: `luacheck lua` (config in `.luacheckrc`; pre-existing warnings in `init.lua`/`utils.lua` are ignored by code — drop a code once fixed). Locally, install with `luarocks --lua-version 5.1 --lua-dir $(brew --prefix luajit) install --local luacheck` (the Lua 5.5 build of luacheck crashes).
- CI: `.github/workflows/ci.yml` runs luacheck and `scripts/test.sh` on push to `main` and on PRs, against Neovim v0.10.4 and stable with Taskwarrior 3.5.0 built from the release tarball (cached; Ubuntu's apt only has 2.6); the stable leg enforces 100% line coverage.

## Key APIs Used
- `vim.system(args, { text = true })` sync (`:wait()`) and async (callback)
- `vim.json.decode` (safe in fast-event callbacks); `vim.fn.json_decode` in older sync paths
- `nvim_buf_set_extmark` (due virtual text; ephemeral conceal extmarks), `nvim_set_decoration_provider`
- `nvim_set_hl(..., { default = true })` for highlights
