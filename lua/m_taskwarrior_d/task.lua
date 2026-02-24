local M = {}

function M.set_config(opts)
  for k, v in pairs(opts) do
    M[k] = v
  end
end

function M.get_task_by(task_id, return_data)
  if return_data == nil then
    return_data = "uuid"
  end
  local command = string.format("task %s export", task_id)
  local handle = io.popen(command)
  local result = handle:read("*a")
  handle:close()
  local task_info
  if vim == nil then
    local json = require("cjson")
    task_info = json.decode(result)
  else
    task_info = vim.fn.json_decode(result)
  end
  if task_info and #task_info > 0 then
    if return_data == "task" then
      return task_info[1]
    else
      return task_info[1][return_data]
    end
  else
    return nil
  end
end

-- Fetch multiple tasks in a single Taskwarrior invocation.
-- Returns a lookup table: { [uuid] = task_data, ... }
-- Splits into batches to avoid command-line length limits.
local BULK_EXPORT_BATCH_SIZE = 50
function M.bulk_export(uuids)
  if not uuids or #uuids == 0 then
    return {}
  end
  local lookup = {}
  local i = 1
  while i <= #uuids do
    local batch = {}
    local j = i
    while j <= #uuids and j < i + BULK_EXPORT_BATCH_SIZE do
      if j > i then
        table.insert(batch, "or")
      end
      table.insert(batch, "uuid:" .. uuids[j])
      j = j + 1
    end
    local args = { "task" }
    for _, token in ipairs(batch) do
      table.insert(args, token)
    end
    table.insert(args, "export")
    local _, output = M.execute_task_args(args, true)
    if output and #output > 0 then
      local ok, task_list = pcall(vim.fn.json_decode, output)
      if ok and task_list then
        for _, task in ipairs(task_list) do
          if task and task.uuid then
            lookup[task.uuid] = task
          end
        end
      end
    end
    i = j
  end
  return lookup
end

-- Execute taskwarrior directly with an argument list, bypassing the shell entirely.
function M.execute_task_args(args, return_data, print_output)
  local obj = vim.system(args, { text = true }):wait()
  local output = obj.stdout or ""
  if not return_data then
    output = output .. (obj.stderr or "")
  end
  if print_output then print(output) end
  return obj.code, output
end

-- Split a whitespace-delimited string and append each token to args.
-- Handles nil and empty strings safely (no-op).
function M.append_tokens(args, str)
  if not str or #str == 0 then return end
  for token in str:gmatch("%S+") do
    table.insert(args, token)
  end
end

-- Function to add a task
function M.add_task(description)
  description = require("m_taskwarrior_d.utils").trim(description)
  local args = { "task", "rc.verbose=new-uuid", "add" }
  M.append_tokens(args, description)
  local _, result = M.execute_task_args(args, true)
  local task_uuid = string.match(result, "%x*-%x*-%x*-%x*-%x*")
  return task_uuid
end

-- Function to list tasks
function M.list_tasks()
  local _, result = M.execute_task_args({ "task" }, true)
  return result
end

-- Function to mark a task as done
function M.mark_task_done(task_id)
  M.execute_task_args({ "task", task_id, "done" })
end

function M.modify_task(task_id, desc)
  local args = { "task", task_id, "mod" }
  M.append_tokens(args, desc)
  M.execute_task_args(args, false)
end

--Function to modify task's status completed, (pending), deleted, started, canceled
function M.modify_task_status(task_id, new_status)
  if M.status_map[new_status] == "active" then
    M.execute_task_args({ "task", task_id, "modify", "status:pending" })
    M.execute_task_args({ "task", task_id, "start" })
  else
    local status = M.status_map[new_status]
    M.execute_task_args({ "task", task_id, "modify", "status:" .. status })
  end
end

function M.add_task_deps(current_task_id, deps)
  M.execute_task_args({ "task", current_task_id, "modify", "dep:" .. table.concat(deps, ",") })
end

function M.get_blocked_tasks_by(uuid)
  local status, result = M.execute_task_args({ "task", "depends.has:" .. uuid, "export" }, true)
  return status, result
end

function M.get_tasks_by(uuids)
  local tasks = {}
  for _, uuid in ipairs(uuids) do
    local _, result = M.execute_task_args({ "task", uuid, "export" }, true)
    if result then
      if vim == nil then
        local json = require("cjson")
        result = json.decode(result)
      else
        result = vim.fn.json_decode(result)
      end
      if result then
        table.insert(tasks, result[1])
      end
    end
  end
  return true, tasks
end

function M.check_if_task_is_blocked(uuid)
  local _, result = M.execute_task_args({ "task", uuid, "-BLOCKED" }, true)
  if #result > 0 then
    return false
  end
  return true
end

return M
