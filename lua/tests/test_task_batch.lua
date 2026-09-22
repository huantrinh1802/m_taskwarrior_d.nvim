-- Regression tests for the batched-Taskwarrior-call fix (task.get_tasks_bulk,
-- task.uuid_or_filter, task.chunk_list, utils.apply_context_data).
--
-- The bug: batched calls used to build Taskwarrior filter args with
-- `table.concat(chunk, " or ")`, joining multiple UUIDs into a single argv
-- string. Since vim.system bypasses the shell, Taskwarrior received one
-- unparseable token instead of separate filter atoms and silently returned
-- zero tasks for every chunk with 2+ UUIDs.
--
-- Run with:
--   nvim --headless -u NONE -c "lua dofile('lua/tests/test_task_batch.lua')"
-- Exits 0 if every check passes, 1 otherwise.

local this_file = debug.getinfo(1, "S").source:sub(2)
local lua_dir = this_file:match("(.*/)tests/[^/]+$")
package.path = lua_dir .. "?.lua;" .. lua_dir .. "?/init.lua;" .. package.path

local task = require("m_taskwarrior_d.task")

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

local function deep_eq(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return a == b
  end
  for k, v in pairs(a) do
    if not deep_eq(v, b[k]) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

print("== unit: task.chunk_list ==")

check("splits evenly", function()
  local chunks = task.chunk_list({ 1, 2, 3, 4 }, 2)
  assert(deep_eq(chunks, { { 1, 2 }, { 3, 4 } }), vim.inspect(chunks))
end)

check("splits with a remainder", function()
  local chunks = task.chunk_list({ 1, 2, 3, 4, 5 }, 2)
  assert(deep_eq(chunks, { { 1, 2 }, { 3, 4 }, { 5 } }), vim.inspect(chunks))
end)

check("chunk size larger than the list yields one chunk", function()
  local chunks = task.chunk_list({ 1, 2 }, 100)
  assert(deep_eq(chunks, { { 1, 2 } }), vim.inspect(chunks))
end)

check("empty list yields no chunks", function()
  local chunks = task.chunk_list({}, 100)
  assert(#chunks == 0, vim.inspect(chunks))
end)

print("== unit: task.uuid_or_filter ==")

check("single uuid produces one uuid: token, no 'or'", function()
  local filter = task.uuid_or_filter({ "u1" })
  assert(deep_eq(filter, { "uuid:u1" }), vim.inspect(filter))
end)

check("multiple uuids are OR'd as separate argv tokens", function()
  local filter = task.uuid_or_filter({ "u1", "u2", "u3" })
  assert(deep_eq(filter, { "uuid:u1", "or", "uuid:u2", "or", "uuid:u3" }), vim.inspect(filter))
end)

check("never collapses uuids into a single joined string (regression guard)", function()
  -- This is the exact shape of the original bug: table.concat(chunk, " or ")
  -- producing one argv element that Taskwarrior can't parse when vim.system
  -- bypasses the shell.
  local filter = task.uuid_or_filter({ "u1", "u2" })
  for _, token in ipairs(filter) do
    assert(not token:find(" or ", 1, true), "found a shell-joined token: " .. token)
  end
end)

if vim.fn.executable("task") ~= 1 then
  print("== integration: SKIPPED (no `task` binary on PATH) ==")
else
  print("== integration: against an isolated Taskwarrior instance ==")

  -- Point Taskwarrior at a throwaway data directory so this never reads or
  -- writes the real user's tasks.
  local tmp_data = vim.fn.tempname()
  vim.fn.mkdir(tmp_data, "p")
  local tmp_rc = tmp_data .. "/taskrc"
  local rc = assert(io.open(tmp_rc, "w"))
  rc:write("data.location=" .. tmp_data .. "\n")
  rc:close()
  vim.fn.setenv("TASKRC", tmp_rc)
  vim.fn.setenv("TASKDATA", tmp_data)

  local uuids = {}
  for i = 1, 3 do
    local uuid = task.add_task("m_taskwarrior_d batch test task " .. i)
    if uuid and #uuid > 0 then
      table.insert(uuids, uuid)
    end
  end

  check("isolated instance seeded 3 tasks", function()
    assert(#uuids == 3, "expected 3 uuids from add_task, got " .. #uuids)
  end)

  check(
    "get_tasks_bulk_sync returns every task for a multi-uuid batch (regression for the ' or '-join bug)",
    function()
      local tasks = task.get_tasks_bulk_sync(uuids)
      assert(#tasks == #uuids, string.format("expected %d tasks, got %d", #uuids, #tasks))
      local by_uuid = {}
      for _, t in ipairs(tasks) do
        by_uuid[t.uuid] = t
      end
      for _, uuid in ipairs(uuids) do
        assert(by_uuid[uuid], "missing task for uuid " .. uuid)
      end
    end
  )

  check("uuid_or_filter + rc.bulk=0 lets a batched `task mod` apply to every uuid non-interactively", function()
    local args = { "task", "rc.bulk=0" }
    vim.list_extend(args, task.uuid_or_filter(uuids))
    table.insert(args, "mod")
    task.append_tokens(args, "+batchtest")
    local code, output = task.execute_task_args(args)
    assert(code == 0, "task mod exited with code " .. tostring(code) .. ": " .. tostring(output))

    local tasks = task.get_tasks_bulk_sync(uuids)
    assert(#tasks == #uuids, "expected all tasks back after mod, got " .. #tasks)
    for _, t in ipairs(tasks) do
      local has_tag = false
      for _, tag in ipairs(t.tags or {}) do
        if tag == "batchtest" then
          has_tag = true
        end
      end
      assert(has_tag, "task " .. t.uuid .. " is missing the tag applied via batched mod")
    end
  end)

  check("get_tasks_bulk_sync returns nothing for an unknown uuid instead of hanging", function()
    local tasks = task.get_tasks_bulk_sync({ "00000000-0000-0000-0000-000000000000" })
    assert(#tasks == 0, "expected no tasks for an unknown uuid, got " .. #tasks)
  end)

  vim.fn.delete(tmp_data, "rf")
end

print("")
print(string.format("%d passed, %d failed", passed, #failures))
if #failures > 0 then
  os.exit(1)
else
  os.exit(0)
end
