-- frontmatter.lua and :TWSyncNote: one Markdown file = one Taskwarrior task,
-- driven by YAML frontmatter.
--
-- Run with: scripts/test.sh lua/tests/test_frontmatter.lua
-- Needs `yq` (mikefarah/yq v4) on PATH; skipped otherwise.

local this_file = debug.getinfo(1, "S").source:sub(2)
package.path = this_file:match("(.*/)tests/[^/]+$") .. "?.lua;" .. package.path
local H = require("tests.helpers")
local check, eq = H.check, H.eq

if vim.fn.executable("yq") ~= 1 then
  H.skip_suite("no `yq` binary on PATH")
end
H.isolate_taskwarrior()
local plugin = require("m_taskwarrior_d")
local fm = require("m_taskwarrior_d.frontmatter")
local utils = require("m_taskwarrior_d.utils")
local task = require("m_taskwarrior_d.task")
plugin.setup({})
H.track_async(task)

local function note(name, lines)
  H.edit_md(name, lines)
  H.wait_async()
  return vim.api.nvim_get_current_buf()
end

local function uuid_line()
  for _, l in ipairs(H.lines()) do
    local uuid = l:match("^uuid: (%S+)$")
    if uuid then
      return uuid
    end
  end
end

H.section("extract_frontmatter_block")

check("returns the YAML between the fences and the fence rows", function()
  local buf = note("block.md", { "---", "a: 1", "b: 2", "---", "body" })
  eq({ "a: 1\nb: 2", 0, 3 }, { fm.extract_frontmatter_block(buf) })
end)

check("returns nil when the file does not start with a fence", function()
  local buf = note("nofence.md", { "# title", "---", "a: 1", "---" })
  eq(nil, fm.extract_frontmatter_block(buf))
end)

check("warns and returns nil for an unclosed fence", function()
  local buf = note("unclosed.md", { "---", "a: 1" })
  local notes = H.capture_notify(function()
    eq(nil, fm.extract_frontmatter_block(buf))
  end)
  assert(notes[1] and notes[1].msg:find("no closing fence", 1, true), vim.inspect(notes))
end)

H.section("parse_yaml")

check("parses YAML into a table", function()
  eq({ { tw_task = true, tags = { "a", "b" }, n = 3 }, nil }, { fm.parse_yaml("tw_task: true\ntags: [a, b]\nn: 3") })
end)

check("blank YAML is an empty table", function()
  eq({ {}, nil }, { fm.parse_yaml("  \n") })
end)

check("invalid YAML returns yq's error", function()
  local result, err = fm.parse_yaml("a: [unclosed")
  eq(nil, result)
  assert(err and #err > 0, "no error message")
end)

check("output that is not JSON returns the decode error", function()
  local result, err = H.with_stub(vim, "system", function()
    return {
      wait = function()
        return { code = 0, stdout = "not json" }
      end,
    }
  end, function()
    return fm.parse_yaml("a: 1")
  end)
  eq(nil, result)
  assert(err, "no error message")
end)

check("a missing yq binary is reported", function()
  local real = fm.yq_bin
  fm.yq_bin = "no_such_yq_binary"
  local result, err = fm.parse_yaml("a: 1")
  fm.yq_bin = real
  eq(nil, result)
  eq("no_such_yq_binary not found on $PATH", err)
end)

H.section("helpers")

check("is_task_note requires the indicator key to be literally true", function()
  eq(true, fm.is_task_note({ tw_task = true }))
  eq(false, fm.is_task_note({ tw_task = "true" }))
  eq(false, fm.is_task_note({}))
  eq(false, fm.is_task_note("tw_task: true"))
end)

check("get_task_description uses the title, else the file name", function()
  local buf = note("Plan the trip.md", { "" })
  eq("Titled", fm.get_task_description({ title = "Titled" }, buf))
  eq("Plan the trip", fm.get_task_description({ title = "  " }, buf))
  eq("Plan the trip", fm.get_task_description({}, buf))
end)

check("find_key_line finds a key inside the frontmatter only", function()
  local buf = note("keys.md", { "---", "a: 1", "  uuid : x", "---", "uuid: outside" })
  eq(2, fm.find_key_line(buf, 0, 3, "uuid"))
  eq(nil, fm.find_key_line(buf, 0, 3, "missing"))
end)

check("write_uuid_back replaces an existing uuid line or inserts one", function()
  local buf = note("write.md", { "---", "uuid: old", "---" })
  fm.write_uuid_back(buf, "new-uuid", 0, 2)
  eq({ "---", "uuid: new-uuid", "---" }, H.lines())
  buf = note("insert.md", { "---", "a: 1", "---" })
  fm.write_uuid_back(buf, "fresh", 0, 2)
  eq({ "---", "uuid: fresh", "a: 1", "---" }, H.lines())
end)

check("attrs_to_modify maps scalars and tags and skips other lists", function()
  local notes = H.capture_notify(function()
    local kv = fm.attrs_to_modify({
      tw_task = true,
      uuid = "u",
      title = "t",
      project = "Home",
      priority = "H",
      tags = { "a", "b" },
      related = { "x" },
    })
    table.sort(kv)
    eq({ "+a", "+b", "priority:H", "project:Home" }, kv)
  end)
  eq(1, #notes)
  assert(notes[1].msg:find("'related'", 1, true), notes[1].msg)
end)

H.section(":TWSyncNote")

check("a new task note creates a task and writes its uuid back", function()
  note("Write report.md", {
    "---",
    "tw_task: true",
    "project: Work",
    "tags: [writing, q4]",
    "---",
    "Body text.",
  })
  vim.cmd("TWSyncNote")
  local uuid = uuid_line()
  assert(uuid, "no uuid written: " .. vim.inspect(H.lines()))
  eq({ "---", "uuid: " .. uuid, "tw_task: true", "project: Work", "tags: [writing, q4]", "---", "Body text." }, H.lines())
  local t = H.get(uuid)
  table.sort(t.tags)
  eq({ "Write report", "Work", { "q4", "writing" } }, { t.description, t.project, t.tags })
end)

check("re-syncing pushes the frontmatter's title and attributes", function()
  vim.api.nvim_buf_set_lines(0, 2, 4, false, { "tw_task: true", "title: Write the Q4 report", "priority: H" })
  vim.cmd("TWSyncNote")
  local t = H.get(uuid_line())
  eq({ "Write the Q4 report", "H" }, { t.description, t.priority })
  eq(1, #H.export("description:Write"), "re-sync created a second task")
end)

check("a uuid unknown to Taskwarrior is replaced by a new task", function()
  note("stale.md", { "---", "tw_task: true", "uuid: 00000000-0000-0000-0000-000000000000", "---" })
  vim.cmd("TWSyncNote")
  local uuid = uuid_line()
  assert(uuid ~= "00000000-0000-0000-0000-000000000000", "stale uuid kept")
  eq("stale", H.get(uuid).description)
  eq(4, #H.lines())
end)

check("only already-tracked checkboxes in the note body are synced", function()
  local tracked = H.add("tracked in note")
  note("body.md", {
    "---",
    "tw_task: true",
    "---",
    "- [ ] plain checklist item",
    "- [ ] stale text $id{" .. tracked .. "}",
  })
  vim.cmd("TWSyncNote")
  local lines = H.lines()
  eq("- [ ] plain checklist item", lines[5])
  eq("- [ ] tracked in note $id{" .. tracked .. "}", lines[6])
  eq(0, #H.export("description:plain"))
end)

check("notes without the indicator, without frontmatter, or with bad YAML are left alone", function()
  for _, lines in ipairs({
    { "---", "title: not a task", "---" },
    { "# no frontmatter", "- [ ] item" },
  }) do
    note("ignored.md", lines)
    local before = #H.export("")
    vim.cmd("TWSyncNote")
    eq(lines, H.lines())
    eq(before, #H.export(""))
  end
  note("bad.md", { "---", "tw_task: [unclosed", "---" })
  local notes = H.capture_notify(function()
    vim.cmd("TWSyncNote")
  end)
  assert(notes[1] and notes[1].msg:find("frontmatter parse failed", 1, true), vim.inspect(notes))
  eq(vim.log.levels.ERROR, notes[1].level)
end)

check("a synced note gets due marks for its body tasks", function()
  local due = H.add("note due", { "due:now+3d" })
  note("due.md", { "---", "tw_task: true", "---", "- [ ] x $id{" .. due .. "}" })
  vim.cmd("TWSyncNote")
  H.wait_async()
  eq(1, #vim.api.nvim_buf_get_extmarks(0, utils.ns_due_id, { 4, 0 }, { 4, -1 }, {}))
end)

H.finish()
