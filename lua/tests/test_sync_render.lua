-- Regression tests for sync_tasks and buffer rendering after the batching
-- change:
--   1. sync_tasks re-used first-pass line copies, so a child line that
--      check_dependencies had already given an $id{...} was `task add`ed again.
--   2. render_virtual_due_dates cleared marks before its async export, so
--      overlapping renders stacked duplicate marks, and it set marks at line
--      numbers captured before the export (out of range if the buffer shrank).
--   3. Conceal extmarks were only placed on BufEnter, so ids added later
--      (by a sync, typed, pasted) showed their raw UUID.
--
-- Run with:
--   nvim --headless -u NONE -c "lua dofile('lua/tests/test_sync_render.lua')"
-- Exits 0 if every check passes, 1 otherwise. Needs `task` on PATH.

local this_file = debug.getinfo(1, "S").source:sub(2)
local lua_dir = this_file:match("(.*/)tests/[^/]+$")
package.path = lua_dir .. "?.lua;" .. lua_dir .. "?/init.lua;" .. package.path

local passed = 0
local failures = {}

local function check(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("  ok   - " .. name)
  else
    table.insert(failures, { name = name, err = err })
    print("  FAIL - " .. name .. ": " .. tostring(err))
  end
end

local function finish()
  print("")
  print(string.format("%d passed, %d failed", passed, #failures))
  os.exit(#failures > 0 and 1 or 0)
end

if vim.fn.executable("task") ~= 1 then
  print("== SKIPPED (no `task` binary on PATH) ==")
  finish()
end

-- Point Taskwarrior at a throwaway data directory so this never reads or
-- writes the real user's tasks, and keep setup()'s saved-queries file out of
-- the real stdpath("data").
local tmp_dir = vim.fn.tempname()
vim.fn.mkdir(tmp_dir, "p")
local tmp_rc = tmp_dir .. "/taskrc"
local rc = assert(io.open(tmp_rc, "w"))
rc:write("data.location=" .. tmp_dir .. "\n")
rc:close()
vim.fn.setenv("TASKRC", tmp_rc)
vim.fn.setenv("TASKDATA", tmp_dir)
local real_stdpath = vim.fn.stdpath
vim.fn.stdpath = function(what)
  if what == "data" then
    return tmp_dir
  end
  return real_stdpath(what)
end

local plugin = require("m_taskwarrior_d")
local utils = require("m_taskwarrior_d.utils")
local task = require("m_taskwarrior_d.task")
plugin.setup({})

-- Track in-flight async exports so tests can wait for every render callback
-- (including ones fired by BufEnter) to have run. The extra vim.schedule runs
-- after the plugin's own scheduled callback, since vim.schedule is FIFO.
local in_flight = 0
local real_get_tasks_bulk = task.get_tasks_bulk
task.get_tasks_bulk = function(uuids, callback)
  in_flight = in_flight + 1
  real_get_tasks_bulk(uuids, function(tasks)
    callback(tasks)
    vim.schedule(function()
      in_flight = in_flight - 1
    end)
  end)
end
local function wait_for_renders()
  assert(vim.wait(10000, function()
    return in_flight == 0
  end, 10), "timed out waiting for due-date renders")
end

local function export(filter)
  local args = { "task" }
  task.append_tokens(args, filter)
  table.insert(args, "export")
  local obj = vim.system(args, { text = true }):wait()
  return vim.json.decode(obj.stdout ~= "" and obj.stdout or "[]")
end

local function deps_of(t)
  local deps = t.depends or {}
  if type(deps) == "string" then
    deps = vim.split(deps, ",", { trimempty = true })
  end
  return deps
end

local function due_marks(row)
  return vim.api.nvim_buf_get_extmarks(0, utils.ns_due_id, { row, 0 }, { row, -1 }, {})
end

-- Put `lines` after a blank first line and park the cursor there: the cursor
-- line is never concealed (concealcursor is empty by default), so the line
-- under test is screen row 2.
local function set_lines_below_cursor(lines)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.list_extend({ "" }, lines))
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

local function screen_row(row)
  local s = {}
  for col = 1, vim.o.columns do
    table.insert(s, vim.fn.screenstring(row, col))
  end
  return table.concat(s)
end

-- Open a real *.md buffer so the plugin's BufEnter autocmd runs.
local md_file = tmp_dir .. "/test.md"
vim.fn.writefile({ "" }, md_file)
vim.cmd("edit " .. vim.fn.fnameescape(md_file))
wait_for_renders()

print("== sync_tasks ==")

check("syncing a new parent with a new child creates exactly 2 tasks", function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "- [ ] nested parent", "  - [ ] nested child" })
  plugin.sync_tasks()

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local _, parent_uuid = utils.extract_uuid(lines[1])
  local _, child_uuid = utils.extract_uuid(lines[2])
  assert(parent_uuid, "parent line has no $id: " .. lines[1])
  assert(child_uuid, "child line has no $id: " .. lines[2])

  local tasks = export("description:nested")
  assert(#tasks == 2, "expected 2 tasks in Taskwarrior, got " .. #tasks .. ": " .. vim.inspect(tasks))

  local parent = export("uuid:" .. parent_uuid)[1]
  local deps = deps_of(parent)
  assert(#deps == 1 and deps[1] == child_uuid, "parent should depend on the buffer's child, got " .. vim.inspect(deps))
end)

check("re-syncing the same nested list creates no new tasks", function()
  local before = #export("description:nested")
  plugin.sync_tasks()
  local after = #export("description:nested")
  assert(after == before, string.format("task count went from %d to %d", before, after))
end)

check("syncing an existing parent with a new child adds only the child", function()
  local parent_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
  local _, parent_uuid = utils.extract_uuid(parent_line)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { parent_line, "  - [ ] nested second child" })
  plugin.sync_tasks()

  local tasks = export("description:nested")
  assert(#tasks == 3, "expected 3 tasks in Taskwarrior, got " .. #tasks)
  local _, child_uuid = utils.extract_uuid(vim.api.nvim_buf_get_lines(0, 1, 2, false)[1])
  local deps = deps_of(export("uuid:" .. parent_uuid)[1])
  assert(vim.tbl_contains(deps, child_uuid), "parent should depend on the new child, got " .. vim.inspect(deps))
end)

print("== render_virtual_due_dates ==")

local due_uuid = task.add_task("due render task due:tomorrow")
assert(due_uuid and #due_uuid > 0, "could not seed a task with a due date")
local due_line = "- [ ] due render task $id{" .. due_uuid .. "}"

check("overlapping renders leave exactly one due mark", function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { due_line })
  wait_for_renders()
  utils.render_virtual_due_dates()
  utils.render_virtual_due_dates()
  utils.render_virtual_due_dates(0, 1)
  wait_for_renders()
  local marks = due_marks(0)
  assert(#marks == 1, "expected 1 due mark, got " .. #marks)
end)

check("buffer shrinking during the export does not error and marks the moved line", function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "filler 1", "filler 2", due_line })
  wait_for_renders()
  vim.v.errmsg = ""
  utils.render_virtual_due_dates()
  vim.api.nvim_buf_set_lines(0, 0, 2, false, {})
  wait_for_renders()
  assert(vim.v.errmsg == "", "render raised: " .. vim.v.errmsg)
  assert(#due_marks(0) == 1, "expected the due mark on the task's new row 0")
end)

check("lines inserted above during the export shift the mark with the task", function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { due_line })
  wait_for_renders()
  utils.render_virtual_due_dates()
  vim.api.nvim_buf_set_lines(0, 0, 0, false, { "inserted 1", "inserted 2" })
  wait_for_renders()
  assert(#due_marks(0) == 0 and #due_marks(1) == 0, "stale mark left on an inserted line")
  assert(#due_marks(2) == 1, "expected the due mark on the task's new row 2")
end)

print("== conceal ==")

check("an $id added by sync_tasks is concealed without re-entering the buffer", function()
  set_lines_below_cursor({ "- [ ] conceal after sync" })
  plugin.sync_tasks()
  assert(utils.extract_uuid(vim.api.nvim_buf_get_lines(0, 1, 2, false)[1]), "sync did not add an $id")
  vim.cmd("redraw!")
  local row = screen_row(2)
  assert(not row:find("$id{", 1, true), "raw $id still visible: " .. row)
end)

check("a typed/pasted $id is concealed", function()
  set_lines_below_cursor({ due_line })
  vim.cmd("redraw!")
  local row = screen_row(2)
  assert(not row:find("$id{", 1, true), "raw $id still visible: " .. row)
end)

check("$query{...} headers are concealed", function()
  set_lines_below_cursor({ "## Inbox $query{+inbox}" })
  vim.cmd("redraw!")
  local row = screen_row(2)
  assert(not row:find("$query{", 1, true), "raw $query still visible: " .. row)
end)

check("re-entering the buffer stores no conceal extmarks (nothing to duplicate)", function()
  vim.cmd("enew")
  vim.cmd("buffer #")
  local bufnr = vim.api.nvim_get_current_buf()
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, utils.ns_conceal_id, 0, -1, {})
  assert(#marks == 0, "expected no persistent conceal extmarks, got " .. #marks)
end)

check("non-plugin buffers are not concealed", function()
  vim.cmd("enew")
  set_lines_below_cursor({ due_line })
  vim.wo.conceallevel = 2
  vim.cmd("redraw!")
  local row = screen_row(2)
  assert(row:find("$id{", 1, true), "plain buffer was concealed: " .. row)
end)

vim.fn.stdpath = real_stdpath
vim.fn.delete(tmp_dir, "rf")
finish()
