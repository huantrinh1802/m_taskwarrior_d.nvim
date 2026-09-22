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

-- Split a list into chunks of at most `size` elements.
function M.chunk_list(list, size)
  local chunks = {}
  for i = 1, #list, size do
    local chunk = {}
    for j = i, math.min(i + size - 1, #list) do
      table.insert(chunk, list[j])
    end
    table.insert(chunks, chunk)
  end
  return chunks
end

-- Build Taskwarrior filter argv tokens that OR together a list of UUIDs,
-- e.g. {"uuid:u1", "or", "uuid:u2"}.
--
-- These MUST be appended to the args table as separate elements (never
-- table.concat'd into a single string): vim.system bypasses the shell, so a
-- joined "u1 or u2" string is handed to Taskwarrior as one unparseable
-- argument ("The expression could not be evaluated") instead of being split
-- into filter atoms. Each UUID also needs the uuid: attribute prefix -
-- bare UUIDs joined with a separate "or" token fail the same way.
function M.uuid_or_filter(uuids)
  local filter = {}
  for i, uuid in ipairs(uuids) do
    if i > 1 then
      table.insert(filter, "or")
    end
    table.insert(filter, "uuid:" .. uuid)
  end
  return filter
end

-- Fetch many tasks with a single (or chunked) Taskwarrior export.
-- `uuids` is a list of UUID strings. `callback(tasks)` receives the
-- decoded array of task objects asynchronously via vim.system.
function M.get_tasks_bulk(uuids, callback)
  if not uuids or #uuids == 0 then
    callback({})
    return
  end

  local chunks = M.chunk_list(uuids, 100)
  local all_tasks = {}
  local total_chunks = #chunks
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

  for _, chunk in ipairs(chunks) do
    local args = { "task" }
    vim.list_extend(args, M.uuid_or_filter(chunk))
    table.insert(args, "export")
    vim.system(args, { text = true }, function(obj)
      local tasks = {}
      if obj.code == 0 and obj.stdout and #obj.stdout > 0 then
        -- vim.system's callback runs in a fast-event context, where
        -- vim.fn.* calls (like vim.fn.json_decode) are disallowed and throw
        -- E5560. vim.json.decode is a plain Lua/C API and safe to call here.
        local ok, decoded = pcall(vim.json.decode, obj.stdout)
        if ok and decoded then
          tasks = decoded
        end
      else
        vim.schedule(function()
          vim.notify(
            "m_taskwarrior_d: batched task export failed: " .. ((obj.stderr or "") ~= "" and obj.stderr or "unknown error"),
            vim.log.levels.WARN
          )
        end)
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
  -- Wait for the async batch export to complete, bounded so a hung/killed
  -- `task` process can't block the editor forever.
  vim.wait(5000, function() return done end, 10)
  return tasks
end

return M
