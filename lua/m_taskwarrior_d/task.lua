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
  local tasks = M.get_tasks_bulk_sync(uuids)
  return true, tasks
end

function M.check_if_task_is_blocked(uuid)
  local _, result = M.execute_task_args({ "task", uuid, "-BLOCKED" }, true)
  if #result > 0 then
    return false
  end
  return true
end

-- Fetch many tasks with a single (or chunked) Taskwarrior export.
-- `uuids` is a list of UUID strings. `callback(tasks)` receives the
-- decoded array of task objects asynchronously via vim.system.
function M.get_tasks_bulk(uuids, callback)
  if not uuids or #uuids == 0 then
    callback({})
    return
  end

  local chunk_size = 100
  local all_tasks = {}
  local total_chunks = math.ceil(#uuids / chunk_size)
  local completed = 0

  local function on_chunk_done(tasks)
    if tasks then
      for _, task in ipairs(tasks) do
        table.insert(all_tasks, task)
      end
    end
    completed = completed + 1
    if completed == total_chunks then
      callback(all_tasks)
    end
  end

  for i = 1, #uuids, chunk_size do
    local chunk = {}
    for j = i, math.min(i + chunk_size - 1, #uuids) do
      table.insert(chunk, uuids[j])
    end
    local args = { "task", table.concat(chunk, " or "), "export" }
    vim.system(args, { text = true }, function(obj)
      local tasks = {}
      if obj.code == 0 and obj.stdout and #obj.stdout > 0 then
        local ok, decoded = pcall(vim.fn.json_decode, obj.stdout)
        if ok and decoded then
          tasks = decoded
        end
      end
      on_chunk_done(tasks)
    end)
  end
end

-- Synchronous wrapper around get_tasks_bulk for callers that must block.
function M.get_tasks_bulk_sync(uuids)
  local tasks = {}
  local done = false
  M.get_tasks_bulk(uuids, function(result)
    tasks = result
    done = true
  end)
  -- Spin-yield until the async batch export completes.
  while not done do
    vim.wait(10)
  end
  return tasks
end

return M
