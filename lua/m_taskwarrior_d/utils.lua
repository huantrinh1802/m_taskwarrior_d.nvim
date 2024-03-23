local M = {}
M.checkbox_pattern = { lua = "([%-%*%+]) (%[([%sx~%>])%])", vim = "([\\-\\*\\+]) (\\[([\\sx~>])\\])" }
M.id_pattern = { vim = "(\\$id{([0-9a-fA-F\\-]\\+)})", lua = "(%$id@([0-9a-fA-F$-]+)@)" }
M.task_pattern = {
  lua = M.checkbox_pattern.lua .. " (.*) " .. M.id_pattern.lua,
  vim = M.checkbox_pattern.vim .. " (.*) " .. M.id_pattern.vim,
}

function M.encode_patterns(str)
  local lua_pattern = str:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?%s%>]", "%%%1")
  lua_pattern = lua_pattern:gsub(" ", "%s")
  local vim_regex = str:gsub("[\\%*\\.\\[\\^\\$\\(\\)\\|\\?\\+\\s]", "\\%1")
  vim_regex = str:gsub(" ", "\\s")
  return { lua = lua_pattern, vim = vim_regex }
end

function M.set_config(opts)
  for k, v in pairs(opts) do
    M[k] = v
  end
end

function M.trim(st)
  return st:match("^%s*(.*%S)") or ""
end

local function count_leading_spaces(line)
  if line == nil then
    return nil
  end
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
  local task_mod = require("m_taskwarrior_d.task")
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
    local line_number = find_pattern_line(task.uuid)
    new_status, _ = findPair(M.status_map, nil, new_status)
    M.toggle_task_status(nil, line_number, new_status)
    task_mod.modify_task_status(task.uuid, new_status)
  end
end

function M.toggle_task_status(current_line, line_number, new_status)
  if current_line == nil then
    current_line, _ = M.get_line(line_number)
  end
  if new_status == nil then
    -- Get the current buffer number
    local _, _, status = string.match(current_line, M.checkbox_pattern.lua)
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
  local modified_line = string.gsub(current_line, M.status_pattern.lua, "[" .. new_status .. "]")
  -- Set the modified line back to the buffer

  vim.api.nvim_buf_set_lines(0, line_number - 1, line_number, false, { modified_line })
  return new_status
end

function M.add_or_sync_task(line, replace_desc)
  local list_sb, _, status = string.match(line, M.checkbox_pattern.lua)
  local desc = string.gsub(line, M.checkbox_pattern.lua, "")
  local result
  local _, uuid = string.match(line, M.id_part_pattern.lua)
  if uuid == nil then
    uuid = require("m_taskwarrior_d.task").add_task(desc)
    result = line:gsub("%s+$", "") .. " $id{" .. uuid .. "}"
  else
    desc = string.gsub(desc, M.id_part_pattern.lua, "")
    if require("m_taskwarrior_d.task").get_task_by(uuid) == nil then
      line = string.gsub(line, M.id_part_pattern.lua, "")
      uuid = require("m_taskwarrior_d.task").add_task(desc)
      result = line:gsub("%s+$", "") .. " $id{" .. uuid .. "}"
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
        status = new_task_status_sym
        uuid = new_task.uuid
        local spaces = count_leading_spaces(line)
        if replace_desc then
          result = string.rep(" ", spaces or 0)
            .. list_sb
            .. " ["
            .. new_task_status_sym
            .. "] "
            .. M.trim(desc)
            .. " $id{"
            .. new_task.uuid
            .. "}"
        else
          result = string.rep(" ", spaces or 0)
            .. list_sb
            .. " ["
            .. new_task_status_sym
            .. "] "
            .. new_task.description
            .. " $id{"
            .. new_task.uuid
            .. "}"
        end
      else
        result = line
      end
    end
  end
  require("m_taskwarrior_d.task").modify_task_status(uuid, status)
  return result
end

function M.extract_uuid(line)
  if line == nil then
    return nil
  end
  local uuid_pattern = M.id_part_pattern.lua
  local conceal, uuid = string.match(line, uuid_pattern)
  return conceal, uuid
end

function M.check_dependencies(line_number)
  local current_line, _ = M.get_line(line_number)
  if current_line == nil then
    return nil
  end
  local _, current_uuid = M.extract_uuid(current_line)
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
  if next_number_of_spaces == nil then
    return nil, nil
  end
  local _, checkbox, _ = string.match(next_line, M.checkbox_pattern.lua)
  local desc = string.gsub(next_line, M.checkbox_pattern.lua, "")
  local _, next_uuid = M.extract_uuid(next_line)
  if checkbox == nil then
    return nil, nil
  end
  while next_line ~= nil and checkbox ~= nil and current_number_of_spaces < next_number_of_spaces do
    if next_uuid == nil then
      local result = M.add_or_sync_task(desc)
      vim.api.nvim_buf_set_lines(0, line_number + count - 1, line_number + count, false, { result })
    end
    table.insert(deps, next_uuid)
    count = count + 1
    next_line = M.get_line(line_number + count)
    if next_line ~= nil then
      next_number_of_spaces = count_leading_spaces(next_line)
      _, next_uuid = M.extract_uuid(next_line)
      _, checkbox, _ = string.match(next_line, M.checkbox_pattern.lua)
      desc = string.gsub(next_line, M.checkbox_pattern.lua, "")
    end
  end
  return current_uuid, deps
end
return M
