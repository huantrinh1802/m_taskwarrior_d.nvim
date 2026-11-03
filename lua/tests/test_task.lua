-- task.lua: the Taskwarrior CLI wrappers not already covered by
-- test_task_batch.lua.
--
-- Run with: scripts/test.sh lua/tests/test_task.lua

local this_file = debug.getinfo(1, "S").source:sub(2)
package.path = this_file:match("(.*/)tests/[^/]+$") .. "?.lua;" .. package.path
local H = require("tests.helpers")
local check, eq = H.check, H.eq

H.isolate_taskwarrior()
local plugin = require("m_taskwarrior_d")
local task = require("m_taskwarrior_d.task")
plugin.setup({})

H.section("lookups")

local uuid = H.add("lookup me", { "project:look" })

check("get_task_by returns the uuid by default, a field, or the whole task", function()
  eq(uuid, task.get_task_by(uuid))
  eq("look", task.get_task_by(uuid, "project"))
  eq("lookup me", task.get_task_by(uuid, "task").description)
end)

check("get_task_by returns nil for an unknown task", function()
  eq(nil, task.get_task_by("00000000-0000-0000-0000-000000000000"))
end)

check("list_tasks returns Taskwarrior's default report", function()
  assert(task.list_tasks():find("lookup me", 1, true), "task missing from the default report")
end)

check("get_tasks_by returns the matching tasks", function()
  local ok, tasks = task.get_tasks_by({ uuid })
  eq(true, ok)
  eq({ uuid }, vim.tbl_map(function(t)
    return t.uuid
  end, tasks))
end)

H.section("changes")

check("mark_task_done completes a task", function()
  local id = H.add("finish me")
  task.mark_task_done(id)
  eq("completed", H.get(id).status)
end)

check("modify_task splits the new text into words", function()
  local id = H.add("before")
  task.modify_task(id, "after  edit project:words")
  local t = H.get(id)
  eq({ "after edit", "words" }, { t.description, t.project })
end)

check("modify_task_attrs keeps spaces inside a value", function()
  local id = H.add("attrs")
  task.modify_task_attrs(id, { "project:Personal Project", "+tagged" })
  local t = H.get(id)
  eq({ "Personal Project", { "tagged" } }, { t.project, t.tags })
end)

check("modify_task_attrs with nothing to apply runs no command", function()
  local calls = 0
  H.with_stub(task, "execute_task_args", function()
    calls = calls + 1
  end, function()
    task.modify_task_attrs("x", nil)
    task.modify_task_attrs("x", {})
  end)
  eq(0, calls)
end)

check("add_task_deps and the blocked helpers agree", function()
  local parent, child = H.add("blocked parent"), H.add("blocking child")
  eq(false, task.check_if_task_is_blocked(parent))
  task.add_task_deps(parent, { child })
  eq(true, task.check_if_task_is_blocked(parent))
  local _, blocked = task.get_blocked_tasks_by(child)
  eq(parent, vim.json.decode(blocked)[1].uuid)
end)

check("execute_task_args can print and can leave out stderr", function()
  local out, code = H.capture_print(function()
    local c, output = task.execute_task_args({ "task", "_version" }, true, true)
    assert(#output > 0)
    return c
  end)
  eq(0, code)
  assert(#out > 0, "nothing printed")
  local _, with_err = task.execute_task_args({ "task", "nonsense_command_xyz" })
  local _, without_err = task.execute_task_args({ "task", "nonsense_command_xyz" }, true)
  assert(#with_err > #without_err, "stderr was not appended")
end)

H.section("bulk export edge cases")

check("get_tasks_bulk with no uuids calls back with an empty list", function()
  local got
  task.get_tasks_bulk({}, function(tasks)
    got = tasks
  end)
  eq({}, got)
  eq({}, task.get_tasks_bulk_sync(nil))
end)

check("a failed export is reported and treated as no tasks", function()
  for _, stderr in ipairs({ "boom", "" }) do
    local got
    local notes = H.capture_notify(function()
      H.with_stub(vim, "system", function(_, _, on_exit)
        on_exit({ code = 2, stdout = "", stderr = stderr })
      end, function()
        task.get_tasks_bulk({ uuid }, function(tasks)
          got = tasks
        end)
      end)
    end, 1000)
    eq({}, got)
    eq(1, #notes)
    assert(notes[1].msg:find(stderr ~= "" and stderr or "unknown error", 1, true), notes[1].msg)
  end
end)

check("unparseable export output is treated as no tasks", function()
  local got
  H.with_stub(vim, "system", function(_, _, on_exit)
    on_exit({ code = 0, stdout = "not json" })
  end, function()
    task.get_tasks_bulk({ uuid }, function(tasks)
      got = tasks
    end)
  end)
  eq({}, got)
end)

check("get_tasks_bulk_sync gives up after its timeout and says so", function()
  local result
  local notes = H.capture_notify(function()
    H.with_stub(task, "get_tasks_bulk", function() end, function()
      H.with_stub(vim, "wait", function()
        return false
      end, function()
        result = task.get_tasks_bulk_sync({ uuid })
      end)
    end)
  end)
  eq({}, result)
  eq(1, #notes)
  assert(notes[1].msg:find("timed out", 1, true), notes[1].msg)
end)

H.finish()
