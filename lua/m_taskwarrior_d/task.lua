local M = {}

function M.set_config(opts)
  for k, v in pairs(opts) do
    M[k] = v
  end
end
-- Function to execute Taskwarrior command
function M.execute_taskwarrior_command(command, return_data, print_output)
  if not return_data or return_data == nil then
    command = command .. " 2>&1"
  end
  local handle = io.popen(command)
  local result = handle:read("*a")
  if print_output then
    print(result)
  end
  local _, status, code = handle:close()
  return code, result
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
    task_info = json.decode(resulr)
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
-- Function to add a task
function M.add_task(description)
  description = require("m_taskwarrior_d.utils").trim(description)
  local command = string.format("task rc.verbose=new-uuid add \"%s\"", description)
  local _, result = M.execute_taskwarrior_command(command, true)
  local task_uuid = string.match(result, "%x*-%x*-%x*-%x*-%x*")
  return task_uuid
end

-- Function to list tasks
function M.list_tasks()
  local command = "task"
  local _, result = M.execute_taskwarrior_command(command, true)
  return result
end

-- Function to mark a task as done
function M.mark_task_done(task_id)
  local command = string.format("task %s done", task_id)
  local result = M.execute_taskwarrior_command(command)
end

function M.modify_task(task_id, desc)
  local command = string.format("task %s mod \"%s\"", task_id, desc)
  local handle = io.popen(command)
  local result = handle:read("*a")
  handle:close()
end

--Function to modify task's status completed, (pending), deleted, started, canceled
function M.modify_task_status(task_id, new_status)
  local command
  if M.status_map[new_status] == "active" then
    command = string.format("task %s modify status:pending; task %s start", task_id, task_id)
  else
    local status = M.status_map[new_status]
    command = string.format("task %s modify status:%s", task_id, status)
  end
  M.execute_taskwarrior_command(command)
end

function M.add_task_deps(current_task_id, deps)
  local command = string.format("task %s modify dep:%s", current_task_id, table.concat(deps, ","))
  local result = M.execute_taskwarrior_command(command)
end

function M.get_blocked_tasks_by(uuid)
  local command = string.format("task depends.has:%s export", uuid)
  local status, result = M.execute_taskwarrior_command(command, true)
  return status, result
end

function M.get_tasks_by(uuids)
  local tasks = {}
  for _, uuid in ipairs(uuids) do
    local _, result = M.execute_taskwarrior_command(string.format("task %s export", uuid), true)
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
  local command = string.format("task %s -BLOCKED", uuid)
  local _, result = M.execute_taskwarrior_command(command, true)
  if #result > 0 then
    return false
  end
  return true
end

return M
