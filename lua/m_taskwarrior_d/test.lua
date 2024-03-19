local function execute_taskwarrior_command(command, return_data)
  if not return_data or return_data == nil then
    command = command .. " 2>&1"
  end
  local handle = io.popen(command)
  local result = handle:read("*a")
  local _, status, code = handle:close()
  return code, result
end
local function concatWithQuotes(tbl)
  local result = ""
  for i, v in ipairs(tbl) do
    if i > 1 then
      result = result .. ","
    end
    result = result .. '"' .. v .. '"'
  end
  return result
end
function contains(table, item)
  if #table == 0 then
    return false
  end
  for _, value in ipairs(table) do
    if value == item then
      return true
    end
  end
  return false
end

function findPair(table, search_key, search_value)
  for key, value in pairs(table) do
    if (search_value ~= nil and search_value == value) or (search_key ~= nil and search_key == key) then
      return key, value
    end
  end
end
local function calculateFinalStatus(tasks)
  local pendingCount, startedCount, completedCount, deletedCount = 0, 0, 0, 0

  for _, task in ipairs(tasks) do
    if task.status == "pending" then
      if task["tags"] ~= nil and contains(task.tags, "started") then
        startedCount = startedCount + 1
      else
        pendingCount = pendingCount + 1
      end
    elseif task.status == "completed" then
      completedCount = completedCount + 1
    elseif task.status == "deleted" then
      deletedCount = deletedCount + 1
    end
  end

  if pendingCount == #tasks then
    return "pending"
  elseif startedCount > 0 then
    return "started"
  elseif completedCount == #tasks then
    return "completed"
  elseif deletedCount == #tasks then
    return "deleted"
  else
    return "unknown" -- or any other default value
  end
end
function find_pattern_line(pattern)
  -- Get the current buffer number
  pattern = string.gsub(pattern, "%-", "%%-")

  -- Get all lines in the current buffer
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  -- Loop through each line
  for i, line in ipairs(lines) do
    -- Check if the pattern exists in the line
    if string.match(line, pattern) then
      -- Return the line number (1-indexed)
      return i
    end
  end

  -- Pattern not found
  return nil
end
function get_blocked_tasks_by(id)
  local command = string.format("task depends.has:%s export", id)
  local code, result = execute_taskwarrior_command(command, true)
  local tasks
  if vim == nil then
    local json = require("cjson")
    tasks = json.decode(result)
  else
    tasks = vim.fn.json_decode(result)
  end
  local new_statuses = {}
  for _, task in ipairs(tasks) do
    local _, dependencies_result = execute_taskwarrior_command(
      string.format("task export | jq '.[] | select(.uuid | IN(%s))' | jq -s ", concatWithQuotes(task["depends"]))
    )
    if vim == nil then
      local json = require("cjson")
      dependencies = json.decode(dependencies_result)
    else
      dependencies = vim.fn.json_decode(dependencies_result)
    end
    local new_status = calculateFinalStatus(dependencies)
    local line_number = find_pattern_line(task.uuid)
    new_status, _ = findPair(require("m_taskwarrior_d.utils").status_map, nil, new_status)
    require("m_taskwarrior_d.utils").toggle_task_status(nil, line_number, new_status)
    -- for _, dep in ipairs(dependencies) do
    -- end
  end
end

get_blocked_tasks_by("e967b7b8-9844-4905-9cbc-44efe510514c")
-- find_pattern_line("e967b7b8")
