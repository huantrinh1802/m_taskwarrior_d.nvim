-- Shared harness for the headless test suites.
--
-- Usage at the top of a suite:
--   local this_file = debug.getinfo(1, "S").source:sub(2)
--   package.path = this_file:match("(.*/)tests/[^/]+$") .. "?.lua;" .. package.path
--   local H = require("tests.helpers")
--   H.isolate_taskwarrior()
--   ...
--   H.finish()
--
-- Every suite runs in its own Neovim process (see scripts/test.sh), so the
-- plugin's module-level state and setup() never leak between suites.

-- capture_print swaps out the global print.
-- luacheck: globals print

local this_file = debug.getinfo(1, "S").source:sub(2)
local lua_dir = this_file:match("(.*/)tests/[^/]+$")
local repo_dir = vim.fn.fnamemodify(lua_dir, ":p:h:h")
package.path = lua_dir .. "?.lua;" .. lua_dir .. "?/init.lua;" .. package.path

local H = { repo_dir = repo_dir }

local passed = 0
local failures = {}

function H.section(name)
  print("== " .. name .. " ==")
end

function H.check(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("  ok   - " .. name)
  else
    table.insert(failures, { name = name, err = err })
    print("  FAIL - " .. name .. ": " .. tostring(err))
  end
end

function H.finish()
  print("")
  print(string.format("%d passed, %d failed", passed, #failures))
  if H.tmp_dir then
    vim.fn.delete(H.tmp_dir, "rf")
  end
  os.exit(#failures > 0 and 1 or 0)
end

function H.skip_suite(reason)
  print("== SKIPPED (" .. reason .. ") ==")
  os.exit(0)
end

function H.eq(expected, actual, msg)
  if not vim.deep_equal(expected, actual) then
    error(
      string.format("%sexpected %s, got %s", msg and (msg .. ": ") or "", vim.inspect(expected), vim.inspect(actual)),
      2
    )
  end
end

-- Point Taskwarrior and the plugin's stdpath("data") files at a throwaway
-- directory so a suite never reads or writes the real user's tasks.
function H.isolate_taskwarrior()
  if vim.fn.executable("task") ~= 1 then
    H.skip_suite("no `task` binary on PATH")
  end
  H.tmp_dir = vim.fn.tempname()
  vim.fn.mkdir(H.tmp_dir, "p")
  local rc_path = H.tmp_dir .. "/taskrc"
  local rc = assert(io.open(rc_path, "w"))
  rc:write("data.location=" .. H.tmp_dir .. "\n")
  rc:close()
  vim.fn.setenv("TASKRC", rc_path)
  vim.fn.setenv("TASKDATA", H.tmp_dir)
  local real_stdpath = vim.fn.stdpath
  vim.fn.stdpath = function(what)
    if what == "data" then
      return H.tmp_dir
    end
    return real_stdpath(what)
  end
  return H.tmp_dir
end

-- Put nui.nvim on the runtimepath: $NUI_PATH, else a cached clone under
-- .tests/ (cloned on first use).
function H.ensure_nui()
  if pcall(require, "nui.popup") then
    return
  end
  local path = os.getenv("NUI_PATH")
  if path == nil or path == "" then
    path = repo_dir .. "/.tests/nui.nvim"
    if vim.fn.isdirectory(path) == 0 then
      local obj = vim
        .system({ "git", "clone", "--depth", "1", "https://github.com/MunifTanjim/nui.nvim", path }, { text = true })
        :wait()
      assert(obj.code == 0, "could not clone nui.nvim: " .. (obj.stderr or ""))
    end
  end
  vim.opt.runtimepath:append(path)
  package.path = path .. "/lua/?.lua;" .. path .. "/lua/?/init.lua;" .. package.path
  assert(pcall(require, "nui.popup"), "nui.nvim not loadable from " .. path)
end

-- Run `task <args>` directly (not through the plugin) and return stdout.
function H.task(args)
  local cmd = { "task" }
  vim.list_extend(cmd, args)
  local obj = vim.system(cmd, { text = true }):wait()
  return obj.stdout or "", obj.code
end

-- Create a task directly and return its uuid. `attrs` are extra
-- "key:value" argv elements, e.g. { "project:x", "entry:2026-01-01T00:00:01" }.
function H.add(description, attrs)
  local cmd = { "rc.verbose=new-uuid", "add", description }
  vim.list_extend(cmd, attrs or {})
  local out = H.task(cmd)
  local uuid = out:match("%x+%-%x+%-%x+%-%x+%-%x+")
  assert(uuid, "task add failed: " .. out)
  return uuid
end

function H.export(filter)
  local cmd = {}
  for token in (filter or ""):gmatch("%S+") do
    table.insert(cmd, token)
  end
  table.insert(cmd, "export")
  local out = H.task(cmd)
  return vim.json.decode(out ~= "" and out or "[]")
end

function H.get(uuid)
  return H.export("uuid:" .. uuid)[1]
end

-- A task's `depends` as a list (Taskwarrior < 2.6 exports a comma string).
function H.deps_of(t)
  local deps = t.depends or {}
  if type(deps) == "string" then
    deps = vim.split(deps, ",", { trimempty = true })
  end
  return deps
end

function H.lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

function H.set_lines(lines)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
end

-- Buffer lines with the $id{...} markers (and the space before them) removed.
function H.plain_lines()
  return vim.tbl_map(function(l)
    return (l:gsub(" ?%$id{[%x%-]*}", ""))
  end, H.lines())
end

-- Replace tbl[key] with `stub` while running body(), restoring it even if
-- body errors, and return body's results.
local function pack(...)
  return { n = select("#", ...), ... }
end

function H.with_stub(tbl, key, stub, body)
  local real = tbl[key]
  tbl[key] = stub
  local result = pack(pcall(body, real))
  tbl[key] = real
  if not result[1] then
    error(result[2], 2)
  end
  return unpack(result, 2, result.n)
end

-- Call fn and return everything it print()ed (joined with "\n") plus fn's
-- first return value. print is restored even if fn errors.
function H.capture_print(fn)
  local out = {}
  local real_print = print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
      table.insert(parts, tostring(select(i, ...)))
    end
    table.insert(out, table.concat(parts, " "))
  end
  local ok, result = pcall(fn)
  print = real_print
  if not ok then
    error(result, 2)
  end
  return table.concat(out, "\n"), result
end

-- Call fn and return the list of { msg, level } passed to vim.notify,
-- including ones scheduled from async callbacks while waiting `wait_ms`.
function H.capture_notify(fn, wait_ms)
  local notes = {}
  local real_notify = vim.notify
  vim.notify = function(msg, level)
    table.insert(notes, { msg = msg, level = level })
  end
  local ok, err = pcall(fn)
  if wait_ms then
    vim.wait(wait_ms, function()
      return #notes > 0
    end, 10)
  end
  vim.notify = real_notify
  if not ok then
    error(err, 2)
  end
  return notes
end

-- Wrap task.get_tasks_bulk so H.wait_async() can wait for every in-flight
-- export callback (and the vim.schedule'd work it queues) to have run.
local in_flight = 0
function H.track_async(task)
  local real = task.get_tasks_bulk
  task.get_tasks_bulk = function(uuids, callback)
    in_flight = in_flight + 1
    real(uuids, function(tasks)
      callback(tasks)
      vim.schedule(function()
        in_flight = in_flight - 1
      end)
    end)
  end
end

function H.wait_async()
  assert(
    vim.wait(10000, function()
      return in_flight == 0
    end, 10),
    "timed out waiting for async task exports"
  )
end

-- Open a real *.md file (so the plugin's BufEnter autocmd runs) with `lines`.
function H.edit_md(name, lines)
  local path = H.tmp_dir .. "/" .. name
  vim.fn.writefile(lines or { "" }, path)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  return path
end

-- Close every floating window (nui popups) and return to a normal window.
function H.close_floats()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative ~= "" then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
end

-- Content windows of open popups. A nui popup with a border is two floats;
-- the border one is not focusable and is left out.
function H.float_wins()
  return vim.tbl_filter(function(win)
    local config = vim.api.nvim_win_get_config(win)
    return config.relative ~= "" and config.focusable ~= false
  end, vim.api.nvim_list_wins())
end

-- Lines of the current window if it is a popup, else of the newest popup.
function H.float_lines()
  local wins = H.float_wins()
  assert(#wins > 0, "no floating window open")
  local win = vim.tbl_contains(wins, vim.api.nvim_get_current_win()) and vim.api.nvim_get_current_win()
    or wins[#wins]
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
end

-- Press keys as if typed (remapped, so buffer-local maps run).
function H.feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "mx", false)
end

-- Replace nui.input with a fake that records what the plugin mounts:
-- headless, a nui Input mounted from a :command callback does not take
-- focus, so typed keys never reach it. H.inputs holds each mounted input's
-- popup options and input options (prompt, on_submit, ...).
H.inputs = {}
function H.fake_nui_input()
  package.loaded["nui.input"] = setmetatable({}, {
    __call = function(_, popup_options, options)
      return {
        mount = function()
          table.insert(H.inputs, { popup = popup_options, options = options })
        end,
      }
    end,
  })
end

-- Submit `text` to the most recently mounted (fake) input.
function H.submit_input(text)
  local input = H.inputs[#H.inputs]
  assert(input, "no input was mounted")
  table.remove(H.inputs)
  input.options.on_submit(text)
end

return H
