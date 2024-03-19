local M = {}
M.status_map = require('m_taskwarrior_d.utils').status_map

-- Function to execute Taskwarrior command
local function execute_taskwarrior_command(command, return_data)
  if not return_data or return_data == nil then
    command = command .. " 2>&1"
  end
  local handle = io.popen(command)
  local result = handle:read("*a")
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
  local command = string.format("task add %s", description)
  local _, result = execute_taskwarrior_command(command, true)
  local task_number = tonumber(string.match(result, "%d+"))
  return M.get_task_by(task_number)
end

-- Function to list tasks
function M.list_tasks()
  local command = "task"
  local _, result = execute_taskwarrior_command(command, true)
  return result
end

-- Function to mark a task as done
function M.mark_task_done(task_id)
  local command = string.format("task %s done", task_id)
  local result = execute_taskwarrior_command(command)
end

function M.modify_task(task_id, desc)
  local command = string.format("task %s mod %s", task_id, desc)
  local handle = io.popen(command)
  local result = handle:read("*a")
  handle:close()
end

--Function to modify task's status completed, (pending), deleted, started, canceled
function M.modify_task_status(task_id, new_status)
  local command
  if M.status_map[new_status] == "started" then
    command = string.format("task %s modify +started status:pending", task_id)
  else
    local status = M.status_map[new_status]
    command = string.format("task %s modify status:%s -started", task_id, status)
  end
  local status, result = execute_taskwarrior_command(command, true)
end

function M.add_task_deps(current_task_id, deps)
  local command = string.format("task %s modify dep:%s", current_task_id, table.concat(deps, ","))
  local result = execute_taskwarrior_command(command)
end

function M.get_blocked_tasks_by(uuid)
  local command = string.format("task export | jq '.[]|select(.depends | index(\"%s\"))' | jq -s", uuid)
  local status, result = execute_taskwarrior_command(command, true)
  return status, result
end

function M.get_tasks_by(uuids)
  local status, result =
    execute_taskwarrior_command(string.format("task export | jq '.[] | select(.uuid | IN(%s))' | jq -s ", uuids), true)
  return status, result
end

-- Define Neovim commands
-- vim.cmd("command! -nargs=1 TaskAdd lua require('taskwarrior').add_task(<f-args>)")
-- vim.cmd("command! TaskList lua require('taskwarrior').list_tasks()")
-- vim.cmd("command! -nargs=1 TaskDone lua require('taskwarrior').mark_task_done(<f-args>)")

return M
