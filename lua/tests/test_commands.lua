-- init.lua and ui.lua: the :TW* user commands, popups, prompts, saved
-- queries and the scratch split, driven headlessly through nui.nvim.
--
-- Run with: scripts/test.sh lua/tests/test_commands.lua
-- Needs nui.nvim ($NUI_PATH, or it is cloned into .tests/ on first run).

local this_file = debug.getinfo(1, "S").source:sub(2)
package.path = this_file:match("(.*/)tests/[^/]+$") .. "?.lua;" .. package.path
local H = require("tests.helpers")
local check, eq = H.check, H.eq

local tmp_dir = H.isolate_taskwarrior()
H.ensure_nui()
H.fake_nui_input()
local plugin = require("m_taskwarrior_d")
local utils = require("m_taskwarrior_d.utils")
local task = require("m_taskwarrior_d.task")
-- Due marks are switched on only for the check that covers them, so the
-- other checks do not race async renders.
plugin.setup({ display_due_or_scheduled = false })
H.track_async(task)

local saved_queries_file = tmp_dir .. "/m_taskwarrior_d.json"

local function uuid_of(line)
  local _, uuid = utils.extract_uuid(line)
  return uuid
end

-- Start every check from a single normal window on a fresh buffer.
local function reset(lines)
  H.close_floats()
  vim.cmd("silent! only")
  vim.cmd("enew!")
  if lines then
    H.set_lines(lines)
  end
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

local function select_lines(first, last)
  vim.api.nvim_buf_set_mark(0, "<", first, 0, {})
  vim.api.nvim_buf_set_mark(0, ">", last, 0, {})
end

local function write_saved_queries(data)
  local max = 0
  for _, q in ipairs(data) do
    max = math.max(max, #q.name)
  end
  vim.fn.writefile({ vim.json.encode({ saved_queries = { name_max_length = max, data = data } }) }, saved_queries_file)
end

local function read_saved_queries()
  return vim.json.decode(table.concat(vim.fn.readfile(saved_queries_file), "\n"))
end

H.section("setup")

check("setup creates an empty saved-queries file", function()
  eq({ saved_queries = { name_max_length = 0, data = {} } }, read_saved_queries())
end)

check("every :TW command is registered", function()
  local commands = vim.api.nvim_get_commands({})
  for _, name in ipairs({
    "TWToggle", "TWSyncCurrent", "TWSyncTasks", "TWSyncBulk", "TWUpdateCurrent",
    "TWEditTask", "TWView", "TWRunWithCurrent", "TWRun", "TWFocusFloat", "TWEditSavedQueries",
    "TWSavedQueries", "TWRunBulk", "TWQueryTasks", "TWBufQueryTasks", "TWTaskScratch",
    "TWScratchShow", "TWScratchHide", "TWShowDueOrScheduled", "TWShowDueOrScheduledCurrent",
  }) do
    assert(commands[name], name .. " is not defined")
  end
end)

check(":colorscheme restores the plugin's default highlight groups", function()
  vim.cmd("colorscheme default")
  for _, group in ipairs({ "TWConceal", "TWDueDate", "TWDueSoon", "TWDueOverdue" }) do
    assert(next(vim.api.nvim_get_hl(0, { name = group })), group .. " is not defined")
  end
end)

H.section("sync commands")

check("TWSyncCurrent syncs only the cursor line", function()
  reset({ "- [ ] sync current one", "- [ ] sync current two" })
  vim.cmd("TWSyncCurrent")
  assert(uuid_of(H.lines()[1]), "cursor line was not synced")
  eq(nil, uuid_of(H.lines()[2]))
end)

check("TWSyncBulk syncs the selected lines", function()
  reset({ "- [ ] bulk a", "- [ ] bulk b", "- [ ] bulk c" })
  vim.cmd("2,3TWSyncBulk")
  local lines = H.lines()
  eq(nil, uuid_of(lines[1]))
  assert(uuid_of(lines[2]) and uuid_of(lines[3]), vim.inspect(lines))
end)

check("TWSyncTasks applies a query header's context to its tasks", function()
  reset({ "## Work $query{project:ctxsync +ctx}", "- [ ] context one", "- [ ] context two" })
  vim.cmd("TWSyncTasks")
  local tasks = H.export("project:ctxsync +ctx")
  eq(2, #tasks)
end)

check("TWUpdateCurrent pushes the cursor line's description to Taskwarrior", function()
  local uuid = H.add("update before")
  reset({ "- [ ] update after $id{" .. uuid .. "}" })
  vim.cmd("TWUpdateCurrent")
  eq("update after", H.get(uuid).description)
end)

check("TWUpdateCurrent over a range updates every line in it", function()
  local a, b = H.add("range a"), H.add("range b")
  reset({ "- [ ] range a2 $id{" .. a .. "}", "- [ ] range b2 $id{" .. b .. "}" })
  vim.cmd("1,2TWUpdateCurrent")
  eq({ "range a2", "range b2" }, { H.get(a).description, H.get(b).description })
end)

check("TWUpdateCurrent without a range ignores an old visual selection", function()
  local a, b = H.add("stale mark a"), H.add("stale mark b")
  reset({ "- [ ] stale mark a2 $id{" .. a .. "}", "- [ ] stale mark b2 $id{" .. b .. "}" })
  select_lines(1, 1)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.cmd("TWUpdateCurrent")
  eq({ "stale mark a", "stale mark b2" }, { H.get(a).description, H.get(b).description })
end)

check("TWShowDueOrScheduled and its Current variant render due marks", function()
  local uuid = H.add("shown due", { "due:now+3d" })
  reset({ "- [ ] shown due $id{" .. uuid .. "}" })
  local marks = function()
    return #vim.api.nvim_buf_get_extmarks(0, utils.ns_due_id, 0, -1, {})
  end
  vim.cmd("TWShowDueOrScheduledCurrent")
  assert(vim.wait(5000, function()
    return marks() == 1
  end, 10), "no mark from TWShowDueOrScheduledCurrent")
  vim.api.nvim_buf_clear_namespace(0, utils.ns_due_id, 0, -1)
  vim.cmd("TWShowDueOrScheduled")
  assert(vim.wait(5000, function()
    return marks() == 1
  end, 10), "no mark from TWShowDueOrScheduled")
end)

check("with due marks enabled, commands render them without errors", function()
  local uuid = H.add("enabled due", { "due:now+3d", "project:enableddue" })
  plugin._config.display_due_or_scheduled = true
  local ok, err = pcall(function()
    vim.v.errmsg = ""
    for _, command in ipairs({ "TWSyncTasks", "TWEditTask", "TWQueryTasks", "TWBufQueryTasks" }) do
      reset({ "## Due $query{project:enableddue}", "", "- [ ] x $id{" .. uuid .. "}" })
      H.capture_print(function()
        vim.cmd(command)
      end)
      H.wait_async()
    end
    reset()
    H.capture_print(function()
      vim.cmd("TWRun project:enableddue list")
    end)
    H.wait_async()
    eq("", vim.v.errmsg)
  end)
  plugin._config.display_due_or_scheduled = false
  H.close_floats()
  assert(ok, err)
end)

H.section("TWView")

check("TWView shows every field of the task in a markdown popup", function()
  local long_desc = "a description that is long enough to need wrapping in the view table"
  local uuid = H.add(long_desc, { "project:viewing", "+one", "+two", "due:2026-07-15T12:00:00" })
  H.task({ uuid, "annotate", "an annotation that is long enough to wrap onto a second line too" })
  reset({ "- [ ] viewing $id{" .. uuid .. "}" })
  vim.cmd("TWView")
  local text = table.concat(H.float_lines(), "\n")
  for _, want in ipairs({ "project", "viewing", "description", "tags", "- one", "- two", "annotations", "due" }) do
    assert(text:find(want, 1, true), want .. " missing from:\n" .. text)
  end
  local due = os.date("%Y-%m-%d %H:%M", utils.parse_ISO8601_date(H.get(uuid).due))
  assert(text:find(due, 1, true), "due not shown in local time " .. due .. ":\n" .. text)
  eq("markdown", vim.bo.filetype)
  eq(vim.api.nvim_get_current_win(), plugin.current_winid)
end)

check("leaving the TWView popup forgets it, and TWFocusFloat then does nothing", function()
  vim.cmd("wincmd p")
  eq(nil, plugin.current_winid)
  local win = vim.api.nvim_get_current_win()
  vim.cmd("TWFocusFloat")
  eq(win, vim.api.nvim_get_current_win())
end)

check("TWFocusFloat jumps back into an open popup", function()
  local uuid = H.add("focus me")
  reset({ "- [ ] focus $id{" .. uuid .. "}" })
  vim.cmd("TWView")
  local popup_win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(vim.fn.win_getid(1))
  plugin.current_winid = popup_win -- BufLeave cleared it; restore as if still tracked
  vim.cmd("TWFocusFloat")
  eq(popup_win, vim.api.nvim_get_current_win())
end)

check("popup close keys and leaving the window close the popup", function()
  local uuid = H.add("close me")
  reset({ "- [ ] close $id{" .. uuid .. "}" })
  vim.cmd("TWView")
  H.feed("q")
  eq(0, #H.float_wins())
  vim.cmd("TWView")
  vim.cmd("wincmd p")
  vim.cmd("enew")
  eq(0, #H.float_wins())
end)

check("TWView without a task says so", function()
  reset({ "- [ ] no id here" })
  local out = H.capture_print(function()
    vim.cmd("TWView")
  end)
  eq("No task found", out)
end)

H.section("TWEditTask")

-- An $EDITOR that rewrites the description in `task edit`'s file.
local editor = tmp_dir .. "/fake_editor.sh"
vim.fn.writefile({
  "#!/bin/sh",
  [[sed -i.bak 's/^\(  Description: *\).*$/\1edited in editor/' "$1"]],
}, editor)
vim.fn.setfperm(editor, "rwxr-xr-x")
vim.fn.setenv("EDITOR", editor)
vim.fn.setenv("VISUAL", editor)

check("TWEditTask runs `task edit` in a popup and syncs the result back", function()
  local uuid = H.add("edit me")
  reset({ "- [ ] edit me $id{" .. uuid .. "}" })
  vim.cmd("TWEditTask")
  assert(vim.wait(10000, function()
    return #H.float_wins() == 0
  end, 50), "edit popup did not close")
  vim.cmd("stopinsert")
  eq("edited in editor", H.get(uuid).description)
  eq("- [ ] edited in editor $id{" .. uuid .. "}", H.lines()[1])
end)

check("TWEditTask without a task says so", function()
  reset({ "- [ ] nothing to edit" })
  local out = H.capture_print(function()
    vim.cmd("TWEditTask")
  end)
  eq("No task found", out)
end)

H.section("TWRun / TWRunWithCurrent / TWRunBulk")

check("TWRun shows a report in a popup", function()
  H.add("report row", { "project:runreport" })
  reset()
  vim.cmd("TWRun project:runreport list")
  local text = table.concat(H.float_lines(), "\n")
  assert(text:find("report row", 1, true), text)
  assert(plugin.current_winid, "popup not tracked")
  vim.cmd("wincmd p")
  eq(nil, plugin.current_winid)
end)

check("TWRun prints the output of commands that change tasks", function()
  reset()
  local out = H.capture_print(function()
    vim.cmd("TWRun add run printed")
  end)
  assert(out:find("Created task", 1, true), out)
  eq(0, #H.float_wins())
end)

check("TWRun with no output says no task was found", function()
  reset()
  local out = H.capture_print(function()
    vim.cmd("TWRun project:no_such_project_xyz _uuids")
  end)
  eq("No task found", out)
end)

check("TWRun without arguments prompts for them", function()
  H.add("prompted", { "project:prompted" })
  reset()
  vim.cmd("TWRun")
  eq("Run task", H.inputs[#H.inputs].popup.border.text.top)
  H.submit_input("project:prompted list")
  local text = table.concat(H.float_lines(), "\n")
  assert(text:find("prompted", 1, true), text)
end)

check("an empty prompt runs nothing; a non-empty one runs", function()
  reset()
  local ran = {}
  local function prompt()
    plugin.ui.prompt_or_run({
      title = "x",
      run = function(value)
        table.insert(ran, value)
      end,
    })
  end
  prompt()
  H.submit_input("")
  prompt()
  H.submit_input("go")
  eq({ "go" }, ran)
end)

check("TWRunWithCurrent runs a command against the cursor task and re-syncs it", function()
  local uuid = H.add("run with current")
  reset({ "- [ ] run with current $id{" .. uuid .. "}" })
  H.capture_print(function()
    vim.cmd("TWRunWithCurrent start")
  end)
  assert(H.get(uuid).start, "task was not started")
  eq("- [>] run with current $id{" .. uuid .. "}", H.lines()[1])
end)

check("TWRunWithCurrent does nothing on a line without a task", function()
  reset({ "- [ ] plain" })
  vim.cmd("TWRunWithCurrent start")
  eq(0, #H.float_wins())
end)

check("TWRunBulk modifies every task in its range", function()
  local a, b = H.add("bulk run a"), H.add("bulk run b")
  reset({ "- [ ] a $id{" .. a .. "}", "plain", "- [ ] b $id{" .. b .. "}" })
  H.capture_print(function()
    vim.cmd("1,3TWRunBulk mod +bulkrun")
  end)
  eq(2, #H.export("+bulkrun"))
end)

check("TWRunBulk ignores commands that do not change tasks", function()
  local calls = 0
  H.with_stub(task, "execute_task_args", function()
    calls = calls + 1
    return 0, ""
  end, function()
    plugin.run_task_bulk({ "info" })
  end)
  eq(0, calls)
end)

check("TWRunBulk without arguments prompts for them and keeps its range", function()
  local a = H.add("bulk prompt")
  reset({ "plain", "- [ ] a $id{" .. a .. "}" })
  vim.cmd("2TWRunBulk")
  H.capture_print(function()
    H.submit_input("mod +bulkprompt")
  end)
  eq(1, #H.export("+bulkprompt"))
end)

H.section("saved queries")

check("TWEditSavedQueries without a saved-queries file says so", function()
  vim.fn.delete(saved_queries_file)
  local out = H.capture_print(function()
    vim.cmd("TWEditSavedQueries")
  end)
  eq("No saved queries found", out)
end)

check("TWEditSavedQueries lists queries and :write saves the edits", function()
  write_saved_queries({ { name = "inbox", query = "+inbox" }, { name = "work", query = "project:work" } })
  reset()
  vim.cmd("TWEditSavedQueries")
  eq({ "inbox | +inbox", "work  | project:work" }, H.float_lines())
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "renamed inbox | +inbox", "work | project:work +next" })
  vim.cmd("write")
  eq({
    saved_queries = {
      name_max_length = 13,
      data = { { name = "renamed inbox", query = "+inbox" }, { name = "work", query = "project:work +next" } },
    },
  }, read_saved_queries())
  eq(0, #H.float_wins())
end)

check("leaving the saved-queries popup closes it", function()
  reset()
  vim.cmd("TWEditSavedQueries")
  vim.cmd("wincmd p")
  eq(0, #H.float_wins())
  eq(nil, plugin.current_winid)
end)

check("TWSavedQueries does nothing without saved queries", function()
  vim.fn.delete(saved_queries_file)
  reset()
  vim.cmd("TWSavedQueries")
  eq(0, #H.float_wins())
end)

check("choosing a saved query runs it", function()
  H.add("saved query hit", { "project:savedq" })
  write_saved_queries({ { name = "savedq", query = "project:savedq|list" } })
  reset()
  vim.cmd("TWSavedQueries")
  H.feed("<CR>")
  local text = table.concat(H.float_lines(), "\n")
  assert(text:find("saved query hit", 1, true), text)
end)

H.section("scratch split")

check("TWScratchShow and TWScratchHide need a scratch window", function()
  reset()
  local out = H.capture_print(function()
    vim.cmd("TWScratchShow")
    vim.cmd("TWScratchHide")
  end)
  eq("No scratch window\nNo scratch window", out)
end)

check("choosing a saved query in TWTaskScratch renders it in a split", function()
  H.add("scratch hit", { "project:scratchq" })
  write_saved_queries({ { name = "scratch", query = "project:scratchq" } })
  reset()
  vim.cmd("TWTaskScratch")
  H.feed("<CR>")
  local text = table.concat(H.plain_lines(), "\n")
  assert(text:find("$query{project:scratchq}", 1, true), text)
  assert(text:find("- [ ] scratch hit", 1, true), text)
end)

check("TWScratchHide and TWScratchShow hide and reshow the split", function()
  local wins = #vim.api.nvim_list_wins()
  vim.cmd("TWScratchHide")
  eq(wins - 1, #vim.api.nvim_list_wins())
  vim.cmd("TWScratchShow")
  eq(wins, #vim.api.nvim_list_wins())
end)

check("starting a new scratch replaces the old one", function()
  local before = plugin.scratch
  plugin.start_scratch("project:scratchq")
  assert(plugin.scratch ~= before, "scratch not replaced")
end)

H.finish()
