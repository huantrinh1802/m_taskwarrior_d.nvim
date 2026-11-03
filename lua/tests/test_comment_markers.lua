-- comment_prefix/comment_suffix: markers wrapped as <!-- $id{...} --> so they
-- are hidden in rendered Markdown. Every parser reads the patterns derived
-- from these options, so the whole sync/query/conceal path is re-checked.
--
-- Run with: scripts/test.sh lua/tests/test_comment_markers.lua

local this_file = debug.getinfo(1, "S").source:sub(2)
package.path = this_file:match("(.*/)tests/[^/]+$") .. "?.lua;" .. package.path
local H = require("tests.helpers")
local check, eq = H.check, H.eq

H.isolate_taskwarrior()
local plugin = require("m_taskwarrior_d")
local utils = require("m_taskwarrior_d.utils")
plugin.setup({ comment_prefix = "<!--", comment_suffix = "-->", display_due_or_scheduled = false })
vim.opt.shiftwidth = 2

local function uuid_of(line)
  local _, uuid = utils.extract_uuid(line)
  return uuid
end

check("sync wraps new $id markers in the comment", function()
  H.set_lines({ "- [ ] commented parent", "  - [ ] commented child" })
  plugin.sync_tasks()
  local lines = H.lines()
  local parent, child = uuid_of(lines[1]), uuid_of(lines[2])
  eq("- [ ] commented parent <!-- $id{" .. parent .. "} -->", lines[1])
  eq("  - [ ] commented child <!-- $id{" .. child .. "} -->", lines[2])
  eq({ child }, H.deps_of(H.get(parent)))
end)

check("re-syncing a commented line keeps it unchanged", function()
  local before = H.lines()
  plugin.sync_tasks()
  eq(before, H.lines())
end)

check("a bare $id marker is not recognised with comments configured", function()
  eq(nil, uuid_of("- [ ] t $id{0a-1b-2c-3d-4e}"))
  eq("0a-1b-2c-3d-4e", uuid_of("- [ ] t <!-- $id{0a-1b-2c-3d-4e} -->"))
end)

check("queries need the commented header and render commented markers", function()
  H.add("commented query hit", { "project:commented" })
  H.set_lines({ "## Q <!-- $query{project:commented} -->" })
  vim.cmd("TWQueryTasks")
  local lines = H.lines()
  eq(4, #lines)
  assert(lines[3]:match("^%- %[ %] commented query hit <!%-%- %$id{[%x%-]+} %-%->$"), lines[3])
end)

check("conceal covers the whole commented marker", function()
  local line = "- [ ] t <!-- $id{0a-1b-2c-3d-4e} -->"
  local pos = utils.conceal_positions(line)
  eq(1, #pos)
  eq("<!-- $id{0a-1b-2c-3d-4e} -->", line:sub(pos[1].start_col + 1, pos[1].end_col))
end)

check("the scratch header uses the comment markers", function()
  H.ensure_nui()
  local rendered
  H.with_stub(vim, "cmd", function(cmd)
    if cmd == "TWQueryTasks" then
      rendered = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
    elseif not cmd:match("^edit ") then
      vim.api.nvim_command(cmd)
    end
  end, function()
    plugin.start_scratch("project:commented")
  end)
  eq("# Task <!-- $query{project:commented} -->", rendered)
end)

H.finish()
