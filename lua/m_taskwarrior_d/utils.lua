local M = {}
M.task_statuses = { " ", ">", "x", "~" }
M.status_map = { [" "] = "pending", [">"] = "started", ["x"] = "completed", ["~"] = "deleted" }
M.task_pattern = { lua = "([%-%*%+]) (%[([%sx~>])%])", vim = "([\\-\\*\\+]) (\\[([\\sx~>])\\])" }
M.id_pattern = { vim = "(\\$id@([0-9a-fA-F\\-]\\+)@)", lua = "(%$id@([0-9a-fA-F$-]+)@)" }

local function count_leading_spaces(line)
  local count = 0
  for i = 1, #line do
    if line:sub(i, i) == " " then
      count = count + 1
    else
      break
    end
  end
  return count
end

function M.modify_task(parts)
  -- Get the current buffer
  local bufnr = vim.api.nvim_get_current_buf()

  -- Get the lines in the buffer
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Iterate through each line to get the number of leading spaces

  -- Modify the lines
  local task_pattern = "[%-%*%+] %[%s%]"
  local uuid_pattern = "#%([0-9a-fA-F%-]+%)"
  for i, line in ipairs(lines) do
    if string.find(line, uuid_pattern) ~= nil and string.match(line, task_pattern) then
      lines[i] = line .. "#hahaha"
    end
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

function M.get_line(line_number)
  -- Get the current line number if not provided
  if line_number == nil then
    line_number = vim.api.nvim_win_get_cursor(0)[1]
  end

  -- Get the current line content
  local current_line = vim.api.nvim_buf_get_lines(0, line_number - 1, line_number, false)[1]
  return current_line, line_number
end

function findIndex(table, searchString)
  for i, value in ipairs(table) do
    if value == searchString then
      return i
    end
  end
  return nil -- Return nil if the string is not found in the table
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

local function concat_with_quotes(tbl)
  local result = ""
  for i, v in ipairs(tbl) do
    if i > 1 then
      result = result .. ","
    end
    result = result .. '"' .. v .. '"'
  end
  return result
end

local function calculate_final_status(tasks)
  local pendingCount, startedCount, completedCount, deletedCount = 0, 0, 0, 0
  for _, task in ipairs(tasks) do
    print(task.status)
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
  if startedCount > 0 then
    return "started"
  elseif pendingCount > 0 then
    return "pending"
  elseif completedCount > 0 then
    return "completed"
  elseif deletedCount > 0 then
    return "deleted"
  else
    return "unknown" -- or any other default value
  end
end

local function find_pattern_line(pattern)
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

function M.update_related_tasks_statuses(uuid)
  local task_mod = require('m_taskwarrior_d.task')
  local _, result = task_mod.get_blocked_tasks_by(uuid)
  local tasks
  if vim == nil then
    local json = require("cjson")
    tasks = json.decode(result)
  else
    tasks = vim.fn.json_decode(result)
  end
  for _, task in ipairs(tasks) do
    local _, dependencies_result = task_mod.get_tasks_by(concat_with_quotes(task["depends"]))
    local dependencies
    if vim == nil then
      local json = require("cjson")
      dependencies = json.decode(dependencies_result)
    else
      dependencies = vim.fn.json_decode(dependencies_result)
    end
    local new_status = calculate_final_status(dependencies)
    print(new_status)
    local line_number = find_pattern_line(task.uuid)
    new_status, _ = findPair(M.status_map, nil, new_status)
    print(new_status)
    M.toggle_task_status(nil, line_number, new_status)
    task_mod.modify_task_status(task.uuid, new_status)
    -- for _, dep in ipairs(dependencies) do
    -- end
  end
end

function M.toggle_task_status(current_line, line_number, new_status)
  if current_line == nil then
    current_line, _ = M.get_line(line_number)
  end
  if new_status == nil then
    -- Get the current buffer number
    local task_pattern = "([%-%*%+]) (%[([%sx~>])%])"
    local _, checkbox, status = string.match(current_line, task_pattern)
    if status == nil then
      return nil
    end
    local status_index = findIndex(M.task_statuses, status)
    if status_index == #M.task_statuses then
      new_status = M.task_statuses[1]
    else
      new_status = M.task_statuses[status_index + 1]
    end
  end
  local modified_line = string.gsub(current_line, "%[[%sx~%>]%]", "[" .. new_status .. "]")
  -- Set the modified line back to the buffer

  vim.api.nvim_buf_set_lines(0, line_number - 1, line_number, false, { modified_line })
  return new_status
end

function M.add_or_sync_task(line)
  local list_sb, checkbox, status = string.match(line, M.task_pattern.lua)
  local desc = string.gsub(line, M.task_pattern.lua, "")
  local result
  local _, uuid = string.match(line, M.id_pattern.lua)
  if uuid == nil then
    result = line:gsub("%s+$", "") .. " $id@" .. require("m_taskwarrior_d.task").add_task(desc) .. "@"
  else
    desc = string.gsub(desc, M.id_pattern.lua, "")
    if require("m_taskwarrior_d.task").get_task_by(uuid) == nil then
      line = string.gsub(line, M.id_pattern.lua, "")
      result = line:gsub("%s+$", "") .. " $id@" .. require("m_taskwarrior_d.task").add_task(desc) .. "@"
    else
      local new_task = require("m_taskwarrior_d.task").get_task_by(uuid, "task")
      if new_task then
        local started = false
        if new_task.status == "pending" and new_task["tags"] ~= nil then
          started = contains(new_task["tags"], "started")
        end
        local new_task_status_sym
        if not started then
          new_task_status_sym, _ = findPair(M.status_map, nil, new_task.status)
        else
          new_task_status_sym = ">"
        end
        local spaces = count_leading_spaces(line)
        result = string.rep(" ", spaces)
          .. list_sb
          .. " ["
          .. new_task_status_sym
          .. "] "
          .. new_task.description
          .. " $id@"
          .. new_task.uuid
          .. "@"
        -- result = line:gsub("(%[([%sx~%>])%])", "[" .. new_task_status_sym .. "]")
      else
        result = line
      end
    end
  end
  return result
end

local function extract_uuid(line)
  local uuid_pattern = "($id@(.*)@)"
  local conceal, uuid = string.match(line, uuid_pattern)
  return conceal, uuid
end

function M.check_dependencies(line_number)
  local current_line, _ = M.get_line(line_number)
  local _, current_uuid = extract_uuid(current_line)
  local current_number_of_spaces = count_leading_spaces(current_line)
  local deps = {}
  if current_uuid == nil then
    return nil
  end
  local count = 1
  local next_line = M.get_line(line_number + 1)
  if next_line == nil then
    return nil, nil
  end
  local next_number_of_spaces = count_leading_spaces(next_line)
  local _, next_uuid = extract_uuid(next_line)
  while current_number_of_spaces < next_number_of_spaces do
    table.insert(deps, next_uuid)
    count = count + 1
    next_line = M.get_line(line_number + count)
    next_number_of_spaces = count_leading_spaces(next_line)
    _, next_uuid = extract_uuid(next_line)
  end
  return current_uuid, deps
end
return M
