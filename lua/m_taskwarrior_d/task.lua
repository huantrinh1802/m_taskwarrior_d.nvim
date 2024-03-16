local M = {}

-- Function to execute Taskwarrior command
local function execute_taskwarrior_command(command)
  local handle = io.popen(command)
  local result = handle:read("*a")
  handle:close()
  return result
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
-- Function to add a task
function M.add_task(description)
  local command = string.format("task add %q", description)
  local result = execute_taskwarrior_command(command)
  local task_number = tonumber(string.match(result, "%d+"))
  return M.get_task_uuid(task_number)
end

-- Function to list tasks
function M.list_tasks()
  local command = "task"
  local result = execute_taskwarrior_command(command)
  print(result)
end

-- Function to mark a task as done
function M.mark_task_done(task_id)
  local command = string.format("task %s done", task_id)
  local result = execute_taskwarrior_command(command)
  print(result)
end

-- Define Neovim commands
-- vim.cmd("command! -nargs=1 TaskAdd lua require('taskwarrior').add_task(<f-args>)")
-- vim.cmd("command! TaskList lua require('taskwarrior').list_tasks()")
-- vim.cmd("command! -nargs=1 TaskDone lua require('taskwarrior').mark_task_done(<f-args>)")

return M
