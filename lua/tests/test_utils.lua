-- utils.lua: parsing helpers, add_or_sync_task branches, query context
-- modifications, due-date virtual text and conceal bookkeeping.
--
-- Run with: scripts/test.sh lua/tests/test_utils.lua

local this_file = debug.getinfo(1, "S").source:sub(2)
package.path = this_file:match("(.*/)tests/[^/]+$") .. "?.lua;" .. package.path
local H = require("tests.helpers")
local check, eq = H.check, H.eq

H.isolate_taskwarrior()
local plugin = require("m_taskwarrior_d")
local utils = require("m_taskwarrior_d.utils")
local task = require("m_taskwarrior_d.task")
plugin.setup({})
H.track_async(task)

local function uuid_of(line)
  local _, uuid = utils.extract_uuid(line)
  return uuid
end

H.section("small helpers")

check("trim strips surrounding whitespace and maps blank to empty", function()
  eq("a b", utils.trim("  a b \t"))
  eq("", utils.trim("   "))
end)

check("contains finds items and handles empty lists", function()
  eq(false, utils.contains({}, "a"))
  eq(true, utils.contains({ "a", "b" }, "b"))
  eq(false, utils.contains({ "a" }, "z"))
end)

check("findIndex and findPair look up by value or key", function()
  eq(2, findIndex({ "x", "y" }, "y"))
  eq(nil, findIndex({ "x" }, "nope"))
  eq({ ">", "active" }, { findPair(utils.status_map, nil, "active") })
  eq({ "x", "completed" }, { findPair(utils.status_map, "x") })
  eq(nil, findPair(utils.status_map, nil, "nope"))
end)

check("encode_patterns escapes Lua magic characters", function()
  local p = utils.encode_patterns("<!-- a.b -->")
  assert(("x <!-- a.b --> y"):find(p.lua), "pattern does not match its own text: " .. p.lua)
  assert(not ("<!-- aXb -->"):find(p.lua), ". was not escaped: " .. p.lua)
end)

check("get_line defaults to the cursor line", function()
  H.set_lines({ "one", "two" })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  eq({ "two", 2 }, { utils.get_line() })
  eq({ "one", 1 }, { utils.get_line(1) })
end)

check("extract_uuid returns nil for nil or marker-less lines", function()
  eq(nil, utils.extract_uuid(nil))
  eq(nil, uuid_of("- [ ] no marker"))
  eq("0a-1b-2c-3d-4e", uuid_of("- [ ] t $id{0a-1b-2c-3d-4e}"))
end)

check("convert_timestamp_utc_local gives the local time of a UTC timestamp", function()
  for _, ts in ipairs({ "20260115T120000Z", "20260715T120000Z" }) do
    local t = utils.convert_timestamp_utc_local(ts)
    eq(utils.parse_ISO8601_date(ts), os.time(t), ts)
  end
end)

check("toggle_task_status cycles through task_statuses and wraps around", function()
  H.set_lines({ "- [~] wrap" })
  eq(" ", utils.toggle_task_status(nil, 1))
  eq("- [ ] wrap", H.lines()[1])
  eq(">", utils.toggle_task_status(nil, 1))
  eq("x", utils.toggle_task_status(nil, 1, "x"))
  eq("- [x] wrap", H.lines()[1])
end)

H.section("add_or_sync_task")

check("a new line gets a task and an $id marker", function()
  local line, uuid = utils.add_or_sync_task("- [ ] fresh task  ")
  eq("- [ ] fresh task $id{" .. uuid .. "}", line)
  eq("fresh task", H.get(uuid).description)
end)

check("an $id unknown to Taskwarrior is replaced with a new task", function()
  local ghost = "00000000-0000-0000-0000-000000000000"
  local line, uuid = utils.add_or_sync_task("- [ ] ghost $id{" .. ghost .. "}")
  assert(uuid ~= ghost and uuid_of(line) == uuid, line)
  eq("ghost", H.get(uuid).description)
end)

check("Taskwarrior's description and status overwrite the buffer's", function()
  local uuid = H.add("from taskwarrior")
  H.task({ uuid, "start" })
  local line = utils.add_or_sync_task("  * [ ] stale text $id{" .. uuid .. "}")
  eq("  * [>] from taskwarrior $id{" .. uuid .. "}", line)
end)

check("replace_desc pushes the buffer's description to Taskwarrior", function()
  local uuid = H.add("old words")
  local line = utils.add_or_sync_task("- [ ] new words $id{" .. uuid .. "}", true)
  eq("- [ ] new words $id{" .. uuid .. "}", line)
  eq("new words", H.get(uuid).description)
end)

check("a task that vanishes between lookups leaves the line unchanged", function()
  local uuid = H.add("vanishing")
  local line = "- [ ] vanishing $id{" .. uuid .. "}"
  local calls = 0
  local result = H.with_stub(task, "get_task_by", function()
    calls = calls + 1
    return calls == 1 and uuid or nil
  end, function()
    return utils.add_or_sync_task(line)
  end)
  eq(line, result)
end)

H.section("query context modifications (apply_context_data)")

-- Run apply_context_data on a buffer and return the `mod` tokens it sends.
local function context_mods(lines)
  H.set_lines(lines)
  local sent = {}
  H.with_stub(task, "execute_task_args", function(args)
    local mods = {}
    local after_mod = false
    for _, a in ipairs(args) do
      if after_mod then
        table.insert(mods, a)
      end
      after_mod = after_mod or a == "mod"
    end
    table.insert(sent, mods)
    return 0, ""
  end, function()
    utils.apply_context_data(lines[1], 1)
  end)
  return sent
end

local u1, u2 = "1a-1a-1a-1a-1a", "2b-2b-2b-2b-2b"

check("tags and attr:value tokens are applied; filter-only tokens are not", function()
  local filter = "project:Home +work -old priority:H status:pending uuid:x due.before:eom urgency>5 "
    .. "( or ) and xor ! /regex/ description:\"a b\""
  eq({ { "project:Home", "+work", "-old", "priority:H" } }, context_mods({
    "## Q $query{" .. filter .. "}",
    "- [ ] a $id{" .. u1 .. "}",
  }))
end)

check("quoted values keep escaped quotes and backslashes", function()
  eq({ { "project:it's", "tag_x:a\\b", "note:a\\nb" } }, context_mods({
    [[## Q $query{'project:it\'s' "tag_x:a\\b" "note:a\nb"}]],
    "- [ ] a $id{" .. u1 .. "}",
  }))
end)

check("an unterminated quote still yields its token", function()
  eq({ { "project:open" } }, context_mods({ "## Q $query{'project:open}", "- [ ] a $id{" .. u1 .. "}" }))
end)

-- Run apply_context_data on a buffer and return each full command it runs.
local function context_commands(lines)
  H.set_lines(lines)
  local commands = {}
  H.with_stub(task, "execute_task_args", function(args)
    table.insert(commands, table.concat(args, " "))
    return 0, ""
  end, function()
    utils.apply_context_data(lines[1], 1)
  end)
  return commands
end

local both = "task rc.bulk=0 uuid:" .. u1 .. " or uuid:" .. u2 .. " mod +ctx"

check("applies to every task directly under the header, up to a blank line", function()
  eq({ both }, context_commands({
    "## Q $query{+ctx}",
    "- [ ] a $id{" .. u1 .. "}",
    "- [ ] b $id{" .. u2 .. "}",
    "",
    "- [ ] after $id{3c-3c-3c-3c-3c}",
  }))
end)

check("applies to the task block after a blank line, up to the next blank line", function()
  eq({ both }, context_commands({
    "## Q $query{+ctx}",
    "",
    "- [ ] a $id{" .. u1 .. "}",
    "plain text",
    "- [ ] b $id{" .. u2 .. "}",
    "",
    "- [ ] after $id{3c-3c-3c-3c-3c}",
  }))
end)

check("a block running to the end of the buffer includes its last line", function()
  eq({ both }, context_commands({
    "## Q $query{+ctx}",
    "- [ ] a $id{" .. u1 .. "}",
    "- [ ] b $id{" .. u2 .. "}",
  }))
end)

check("does nothing without tasks, without safe mods, or at the end of the buffer", function()
  eq({}, context_mods({ "## Q $query{+ctx}", "", "no tasks here" }))
  eq({}, context_mods({ "## Q $query{status:pending}", "- [ ] a $id{" .. u1 .. "}" }))
  eq({}, context_mods({ "## Q $query{+ctx}" }))
  eq({}, context_mods({ "## not a query header", "- [ ] a $id{" .. u1 .. "}" }))
end)

check("modifications reach Taskwarrior in chunks of 50", function()
  local lines = { "## Q $query{+bulk project:ctx}", "" }
  for i = 1, 55 do
    table.insert(lines, "- [ ] bulk " .. i .. " $id{" .. H.add("bulk " .. i) .. "}")
  end
  H.set_lines(lines)
  local calls = 0
  local real = task.execute_task_args
  H.with_stub(task, "execute_task_args", function(...)
    calls = calls + 1
    return real(...)
  end, function()
    utils.apply_context_data(lines[1], 1)
  end)
  eq(2, calls)
  local tagged = H.export("+bulk project:ctx")
  eq(55, #tagged)
end)

check("a failed modification is reported", function()
  local uuid = H.add("bad mod target")
  H.set_lines({ "## Q $query{due:not_a_date}", "- [ ] t $id{" .. uuid .. "}" })
  local notes = H.capture_notify(function()
    utils.apply_context_data(H.lines()[1], 1)
  end)
  eq(1, #notes)
  assert(notes[1].msg:find("failed to apply context", 1, true), notes[1].msg)
  eq(vim.log.levels.WARN, notes[1].level)
end)

H.section("due-date virtual text")

local function due_text(row)
  local marks = vim.api.nvim_buf_get_extmarks(0, utils.ns_due_id, { row, 0 }, { row, -1 }, { details = true })
  if #marks == 0 then
    return nil
  end
  return marks[1][4].virt_text[1]
end

local function render(lines)
  H.set_lines(lines)
  H.wait_async()
  utils.render_virtual_due_dates()
  H.wait_async()
end

check("due in more than a day shows days and hours left", function()
  local uuid = H.add("far", { "due:now+3d" })
  render({ "- [ ] far $id{" .. uuid .. "}" })
  local text = due_text(0)
  assert(text[1]:match("^Due: [23] days, %d+ hours left$"), text[1])
  eq("TWDueDate", text[2])
end)

check("due within a day shows hours and minutes left", function()
  local uuid = H.add("soon", { "due:now+2h" })
  render({ "- [ ] soon $id{" .. uuid .. "}" })
  local text = due_text(0)
  assert(text[1]:match("^Due: [12] hours, %d+ minutes left$"), text[1])
  eq("TWDueSoon", text[2])
end)

check("a past due date shows as overdue", function()
  local uuid = H.add("late", { "due:now-26h" })
  render({ "- [ ] late $id{" .. uuid .. "}" })
  local text = due_text(0)
  assert(text[1]:match("^Due: OVERDUE: 1 days, [12] hours ago$"), text[1])
  eq("TWDueOverdue", text[2])
end)

check("a scheduled-only task shows its scheduled date", function()
  local uuid = H.add("planned", { "scheduled:now+3d" })
  render({ "- [ ] planned $id{" .. uuid .. "}" })
  assert(due_text(0)[1]:match("^Scheduled: "), vim.inspect(due_text(0)))
end)

check("completed tasks and tasks without dates get no mark", function()
  local done = H.add("done due", { "due:now+3d" })
  H.task({ done, "done" })
  local plain = H.add("no dates")
  render({ "- [x] done due $id{" .. done .. "}", "- [ ] no dates $id{" .. plain .. "}" })
  eq(nil, due_text(0))
  eq(nil, due_text(1))
end)

check("a range without tasks clears its stale marks", function()
  local uuid = H.add("will vanish", { "due:now+3d" })
  render({ "- [ ] will vanish $id{" .. uuid .. "}" })
  assert(due_text(0), "no mark to clear")
  render({ "plain text now" })
  eq(nil, due_text(0))
end)

check("a buffer wiped while its export runs is skipped without error", function()
  local uuid = H.add("wiped", { "due:now+3d" })
  vim.cmd("enew")
  local bufnr = vim.api.nvim_get_current_buf()
  H.set_lines({ "- [ ] wiped $id{" .. uuid .. "}" })
  vim.v.errmsg = ""
  utils.render_virtual_due_dates()
  vim.cmd("bwipeout! " .. bufnr)
  H.wait_async()
  eq("", vim.v.errmsg)
end)

check("a range that the buffer shrank past during the export is skipped", function()
  local uuid = H.add("shrunk", { "due:now+3d" })
  H.set_lines({ "a", "b", "- [ ] shrunk $id{" .. uuid .. "}" })
  utils.render_virtual_due_dates(2, 3)
  H.set_lines({ "a" })
  H.wait_async()
  eq(0, #vim.api.nvim_buf_get_extmarks(0, utils.ns_due_id, 0, -1, {}))
end)

check("commands that change one line refresh that line's due mark", function()
  for _, command in ipairs({ "TWSyncCurrent", "TWUpdateCurrent", "1TWSyncBulk", "1TWRunBulk mod +x", "TWRunWithCurrent mod +x" }) do
    local uuid = H.add("command due", { "due:now+3d" })
    vim.cmd("enew!")
    H.set_lines({ "- [ ] command due $id{" .. uuid .. "}", "- [ ] second line" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    H.capture_print(function()
      vim.cmd(command)
    end)
    H.wait_async()
    assert(due_text(0), command .. " did not render the mark on its own line")
  end
end)

H.section("buffer bookkeeping")

check("wiping a markdown buffer forgets its conceal and due state", function()
  local path = H.edit_md("wipe.md", { "x" })
  local bufnr = vim.fn.bufnr(path)
  H.wait_async()
  assert(utils.conceal_buffers[bufnr], "markdown buffer was not registered for conceal")
  vim.cmd("bwipeout! " .. bufnr)
  eq(nil, utils.conceal_buffers[bufnr])
end)

H.finish()
