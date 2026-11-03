-- Dependency handling: building and rendering $query{...} dependency trees,
-- writing dependencies from nested checkbox lists, and propagating child
-- statuses to parents.
--
-- Run with: scripts/test.sh lua/tests/test_dependencies.lua

local this_file = debug.getinfo(1, "S").source:sub(2)
package.path = this_file:match("(.*/)tests/[^/]+$") .. "?.lua;" .. package.path
local H = require("tests.helpers")
local check, eq = H.check, H.eq

H.isolate_taskwarrior()
local plugin = require("m_taskwarrior_d")
local utils = require("m_taskwarrior_d.utils")
local task = require("m_taskwarrior_d.task")
plugin.setup({ display_due_or_scheduled = false })
vim.opt.shiftwidth = 2

local function item(uuid, fields)
  return vim.tbl_extend("force", { uuid = uuid, description = uuid, status = "pending", id = 0, entry = "" }, fields or {})
end

local function child_uuids(node)
  local out = {}
  for _, child in ipairs(node) do
    table.insert(out, child.uuid)
  end
  return out
end

local function uuids_in_buffer()
  return vim.tbl_map(function(l)
    local _, u = utils.extract_uuid(l)
    return u
  end, H.lines())
end

H.section("build_hierarchy")

check("a task without dependencies is a leaf with its fields", function()
  local leaf = item("a", { description = "leaf", tags = { "x" } })
  eq({ uuid = "a", desc = "leaf", status = "pending", tags = { "x" } }, utils.build_hierarchy(leaf, {}, { a = leaf }))
end)

check("pending children are ordered by id, highest first", function()
  local lookup = {
    p = item("p", { depends = { "c1", "c3", "c2" } }),
    c1 = item("c1", { id = 1 }),
    c2 = item("c2", { id = 2 }),
    c3 = item("c3", { id = 3 }),
  }
  eq({ "c3", "c2", "c1" }, child_uuids(utils.build_hierarchy(lookup.p, {}, lookup)))
end)

check("children without ids (completed/deleted) are ordered by entry, oldest first", function()
  local lookup = {
    p = item("p", { depends = { "late", "early" } }),
    late = item("late", { status = "completed", entry = "20260102T000000Z" }),
    early = item("early", { status = "completed", entry = "20260101T000000Z" }),
  }
  eq({ "early", "late" }, child_uuids(utils.build_hierarchy(lookup.p, {}, lookup)))
end)

check("a child that depends on its sibling comes first on an id/entry tie", function()
  local lookup = {
    p = item("p", { depends = { "b", "a" } }),
    a = item("a", { depends = { "b" } }),
    b = item("b"),
  }
  local node = utils.build_hierarchy(lookup.p, {}, lookup)
  eq({ "a" }, child_uuids(node), "b is nested under a, so it is visited and not repeated")
  eq({ "b" }, child_uuids(node[1]))
end)

check("dependencies missing from the lookup are skipped", function()
  local lookup = { p = item("p", { depends = { "gone", "c" } }), c = item("c", { id = 1 }) }
  eq({ "c" }, child_uuids(utils.build_hierarchy(lookup.p, {}, lookup)))
end)

check("an already visited dependency is not nested again", function()
  local lookup = { p = item("p", { depends = { "c" } }), c = item("c", { id = 1 }) }
  eq({}, child_uuids(utils.build_hierarchy(lookup.p, { c = true }, lookup)))
end)

H.section("render_tasks")

check("each status renders its checkbox symbol", function()
  local md = utils.render_tasks({
    { uuid = "u1", desc = "pending", status = "pending" },
    { uuid = "u2", desc = "active", status = "pending", start = "20260101T000000Z" },
    { uuid = "u3", desc = "done", status = "completed" },
    { uuid = "u4", desc = "gone", status = "deleted" },
  })
  eq({
    "- [ ] pending $id{u1}",
    "- [>] active $id{u2}",
    "- [x] done $id{u3}",
    "- [~] gone $id{u4}",
  }, md)
end)

check("nested tasks are indented by shiftwidth per level", function()
  local tree = { uuid = "p", desc = "p", status = "pending" }
  tree[1] = { uuid = "c", desc = "c", status = "pending" }
  tree[1][1] = { uuid = "g", desc = "g", status = "pending" }
  eq({ "- [ ] p $id{p}", "  - [ ] c $id{c}", "    - [ ] g $id{g}" }, utils.render_tasks({ tree }))
end)

check("a description with a newline is reported and skipped with its children", function()
  local tree = { uuid = "bad", desc = "two\nlines", status = "pending" }
  tree[1] = { uuid = "c", desc = "c", status = "pending" }
  local out, md = H.capture_print(function()
    return utils.render_tasks({ tree, { uuid = "ok", desc = "ok", status = "pending" } })
  end)
  eq({ "- [ ] ok $id{ok}" }, md)
  assert(out:find("bad", 1, true) and out:find("newline", 1, true), "no warning printed: " .. out)
end)

H.section("query_tasks rendering")

local function seconds(n)
  return "entry:2026-01-01T00:00:" .. string.format("%02d", n)
end

-- top -> middle -> bottom is a chain, as a sync creates it: each child is
-- newer than its parent. left/right share one child. leaf has no
-- dependencies. (Avoid descriptions like "parent": in a filter such as
-- description:parent, Taskwarrior reads the value as the `parent` attribute.)
local bottom = H.add("bottom", { "project:tree", seconds(5) })
local middle = H.add("middle", { "project:tree", seconds(4), "dep:" .. bottom })
H.add("top", { "project:tree", seconds(3), "dep:" .. middle })
H.add("leaf newest", { "project:tree", seconds(9) })
local shared = H.add("shared", { "project:diamond", seconds(8) })
H.add("left", { "project:diamond", seconds(7), "dep:" .. shared })
H.add("right", { "project:diamond", seconds(6), "dep:" .. shared })

local function query(header, ...)
  H.set_lines({ header, ... })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd("TWQueryTasks")
  return H.plain_lines()
end

check("a 3-level dependency chain renders every level, nested roots first", function()
  eq({
    "## Tree $query{project:tree}",
    "",
    "- [ ] top",
    "  - [ ] middle",
    "    - [ ] bottom",
    "- [ ] leaf newest",
    "",
  }, query("## Tree $query{project:tree}"))
end)

check("rendered lines carry the task's $id", function()
  query("## Tree $query{project:tree}")
  eq(bottom, uuids_in_buffer()[5])
end)

check("a child shared by two parents renders once, under the first parent", function()
  eq({
    "## D $query{project:diamond}",
    "",
    "- [ ] left",
    "  - [ ] shared",
    "- [ ] right",
    "",
  }, query("## D $query{project:diamond}"))
end)

check("children outside the query filter are not rendered", function()
  eq({ "## T $query{description:top}", "", "- [ ] top", "" }, query("## T $query{description:top}"))
end)

check("a query with no matches renders an empty block", function()
  eq({ "## None $query{project:nothing_here}", "", "" }, query("## None $query{project:nothing_here}"))
end)

check("re-running a query replaces its block and keeps what follows", function()
  local lines = query("## T $query{description:top}", "", "- [ ] stale line", "  - [x] stale child", "", "# Next")
  eq({ "## T $query{description:top}", "", "- [ ] top", "", "# Next" }, lines)
end)

check("a header directly followed by text gets a blank line, and the text is kept", function()
  eq(
    { "## T $query{description:top}", "", "- [ ] top", "", "some notes" },
    query("## T $query{description:top}", "some notes")
  )
end)

check("the report part of $query{filter|report} is passed after export", function()
  local seen
  H.with_stub(task, "execute_task_args", function(args)
    seen = vim.deepcopy(args)
    return 0, "[]"
  end, function()
    query("## R $query{project:tree +x|next extra}")
  end)
  eq({ "task", "project:tree", "+x", "-TEMPLATE", "export", "next", "extra" }, seen)
end)

check("an invalid query prints No results instead of erroring", function()
  local out = H.capture_print(function()
    query("## Bad $query{project:tree|no_such_report}")
  end)
  eq("No results", out)
end)

check("query_tasks prints No results for missing or non-list output", function()
  H.set_lines({ "## X $query{project:tree}" })
  for _, output in ipairs({ vim.NIL, "", "null", "{}garbage" }) do
    local out = H.with_stub(task, "execute_task_args", function()
      return 1, output ~= vim.NIL and output or nil
    end, function()
      return H.capture_print(function()
        plugin.query_tasks(1, "project:tree", "")
      end)
    end)
    eq("No results", out, "output " .. vim.inspect(output))
  end
end)

check("TWQueryTasks on a line without $query explains what is missing", function()
  H.set_lines({ "just text" })
  local out = H.capture_print(function()
    vim.cmd("TWQueryTasks")
  end)
  assert(out:find("No query found", 1, true), out)
  eq({ "just text" }, H.lines())
end)

check("TWBufQueryTasks renders every query header in the buffer", function()
  H.set_lines({ "## T $query{description:top}", "", "## R $query{description:right}" })
  vim.cmd("TWBufQueryTasks")
  eq({
    "## T $query{description:top}",
    "",
    "- [ ] top",
    "",
    "## R $query{description:right}",
    "",
    "- [ ] right",
    "",
  }, H.plain_lines())
end)

H.section("delete_scoped_tasks")

check("does nothing for a header on the last line", function()
  H.set_lines({ "a", "## q" })
  utils.delete_scoped_tasks(2)
  eq({ "a", "## q" }, H.lines())
end)

check("deletes the task block up to the next non-task line", function()
  H.set_lines({ "## q", "", "- [ ] a", "  - [x] b", "", "text after" })
  utils.delete_scoped_tasks(1)
  eq({ "## q", "", "text after" }, H.lines())
end)

check("deletes to the end of the buffer when no line follows the block", function()
  H.set_lines({ "## q", "", "- [ ] a", "- [ ] b" })
  utils.delete_scoped_tasks(1)
  eq({ "## q", "" }, H.lines())
end)

check("inserts a blank line when the header is followed by text", function()
  H.set_lines({ "## q", "text" })
  utils.delete_scoped_tasks(1)
  eq({ "## q", "", "text" }, H.lines())
end)

H.section("nested sync writes dependencies")

check("each parent depends on its direct children only", function()
  H.set_lines({
    "- [ ] dep root",
    "  - [ ] dep mid one",
    "    - [ ] dep leaf",
    "  - [ ] dep mid two",
    "- [ ] dep sibling",
  })
  plugin.sync_tasks()
  local uuids = uuids_in_buffer()
  eq(5, #uuids)
  local root, mid1, leaf, mid2, sibling = unpack(uuids)
  local root_deps = H.deps_of(H.get(root))
  table.sort(root_deps)
  local want = { mid1, mid2 }
  table.sort(want)
  eq(want, root_deps, "root deps")
  eq({ leaf }, H.deps_of(H.get(mid1)), "mid one deps")
  eq({}, H.deps_of(H.get(mid2)), "mid two deps")
  eq({}, H.deps_of(H.get(sibling)), "sibling deps")
end)

check("check_dependencies returns nil past the buffer, at its end, or before a non-checkbox line", function()
  H.set_lines({ "- [ ] alone", "plain text" })
  eq(nil, utils.check_dependencies(5))
  eq(nil, utils.check_dependencies(1))
  eq(nil, utils.check_dependencies(2))
end)

check("a synced tree renders back identically through a query", function()
  H.set_lines({ "- [ ] rt one +rt", "  - [ ] rt two +rt", "    - [ ] rt three +rt" })
  plugin.sync_tasks()
  eq({
    "## RT $query{+rt}",
    "",
    "- [ ] rt one",
    "  - [ ] rt two",
    "    - [ ] rt three",
    "",
  }, query("## RT $query{+rt}"))
end)

H.section("child status propagates to parents")

-- Sync a parent with two children and return the three uuids.
local function family(name)
  H.set_lines({ "- [ ] " .. name .. " head", "  - [ ] " .. name .. " one", "  - [ ] " .. name .. " two" })
  plugin.sync_tasks()
  return uuids_in_buffer()
end

local function toggle_line(n, times)
  for _ = 1, times or 1 do
    vim.api.nvim_win_set_cursor(0, { n, 0 })
    vim.cmd("TWToggle")
  end
end

local function symbol(n)
  return H.lines()[n]:match("%[(.)%]")
end

check("toggling a blocked parent is refused", function()
  family("blocked")
  local out = H.capture_print(function()
    toggle_line(1)
  end)
  assert(out:find("blocked", 1, true), out)
  eq(" ", symbol(1))
end)

check("starting one child makes the parent active", function()
  local uuids = family("start")
  toggle_line(2) -- " " -> ">"
  eq(">", symbol(2))
  eq(">", symbol(1))
  local head = H.get(uuids[1])
  assert(head.status == "pending" and head.start, "parent not started: " .. vim.inspect(head))
end)

check("completing every child completes the parent", function()
  local uuids = family("finish")
  toggle_line(2, 2) -- " " -> ">" -> "x"
  toggle_line(3, 2)
  eq("x", symbol(1))
  eq("completed", H.get(uuids[1]).status)
end)

check("completed plus deleted children complete the parent", function()
  local uuids = family("mixed")
  toggle_line(2, 2) -- completed
  toggle_line(3, 3) -- deleted
  eq("x", symbol(1))
  eq("completed", H.get(uuids[1]).status)
end)

check("deleting every child deletes the parent", function()
  local uuids = family("drop")
  toggle_line(2, 3)
  toggle_line(3, 3)
  eq("~", symbol(1))
  eq("deleted", H.get(uuids[1]).status)
end)

check("cycling a child back to pending makes the parent pending", function()
  local uuids = family("cycle")
  toggle_line(2, 4) -- " " -> ">" -> "x" -> "~" -> " "
  eq(" ", symbol(2))
  eq(" ", symbol(1))
  eq("pending", H.get(uuids[1]).status)
end)

check("a parent that is not in the buffer is updated in Taskwarrior only", function()
  local uuids = family("offscreen")
  vim.api.nvim_buf_set_lines(0, 0, 1, false, {})
  toggle_line(1)
  eq(">", symbol(1))
  assert(H.get(uuids[1]).start, "parent was not started")
end)

check("toggling a line that is not a checkbox does nothing", function()
  H.set_lines({ "plain" })
  toggle_line(1)
  eq({ "plain" }, H.lines())
end)

H.finish()
