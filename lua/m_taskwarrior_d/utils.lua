local M = {}
M.checkbox_pattern = {
  lua = "([%-%*%+]) (%[([%sx~%>])%])",
  vim = "([\\-\\*\\+]) (\\[([\\sx~>])\\])",
}
M.id_pattern = { vim = "(\\$id{([0-9a-fA-F\\-]\\+)})", lua = "(%$id@([0-9a-fA-F$-]+)@)" }
M.task_pattern = {
  lua = M.checkbox_pattern.lua .. " (.*) " .. M.id_pattern.lua,
  vim = M.checkbox_pattern.vim .. " (.*) " .. M.id_pattern.vim,
}
M.task = require("m_taskwarrior_d.task")

function M.convert_timestamp_utc_local(timestamp_utc)
  local year = tonumber(string.sub(timestamp_utc, 1, 4))
  local month = tonumber(string.sub(timestamp_utc, 5, 6))
  local day = tonumber(string.sub(timestamp_utc, 7, 8))
  local hour = tonumber(string.sub(timestamp_utc, 10, 11))
  local min = tonumber(string.sub(timestamp_utc, 12, 13))
  local sec = tonumber(string.sub(timestamp_utc, 14, 15))

  -- Convert UTC time to local time
  local utc_time = os.time({ year = year, month = month, day = day, hour = hour, min = min, sec = sec, dst = true })
  -- Get the local timezone offset in seconds
  local local_tz_offset = os.time() - os.time(os.date("!*t"))

  -- Check if the local timezone is currently observing daylight saving time
  local local_time = os.date("*t", os.time())
  local local_dst = local_time.isdst

  -- Adjust the offset if daylight saving time is in effect
  if local_dst then
    local_tz_offset = local_tz_offset + 3600 -- Add an hour for daylight saving time
  end

  -- Convert UTC time to local time by adding the timezone offset
  return os.date("*t", utc_time + local_tz_offset) -- Convert UTC time to local time
end

function M.encode_patterns(str)
  local lua_pattern = str:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?%s%>]", "%%%1")
  lua_pattern = lua_pattern:gsub(" ", "%s")
  local vim_regex = str:gsub("[\\%*\\.\\[\\^\\$\\(\\)\\|\\?\\+\\s\\-]", "\\%1")
  vim_regex = str:gsub(" ", "\\s")
  return { lua = lua_pattern, vim = vim_regex }
end

function M.set_config(opts)
  M.ns_due_id = vim.api.nvim_create_namespace("due")
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

function M.contains(table, item)
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

-- Tokenize a string into an array of tokens, respecting quoted strings and escape sequences.
-- Handles escaped quotes (\") and escaped backslashes (\\) within quoted strings.
-- Example: 'description:"He said \"hello\""' -> ['description:He said "hello"']
local function tokenize_tw_args(str)
  if not str then
    return {}
  end

  local tokens = {}
  local current = {}
  local quote = nil -- Tracks the current quote type ('"' or "'" or nil if not in quote)

  -- Push the current accumulated characters as a token if non-empty
  local function push()
    if #current > 0 then
      table.insert(tokens, table.concat(current))
      current = {}
    end
  end

  local i = 1
  while i <= #str do
    local ch = str:sub(i, i)

    if quote then
      -- Inside a quoted string: handle escapes and quote termination
      if ch == "\\" and i < #str then
        -- Handle escape sequences: \<quote> or \\
        local next_ch = str:sub(i + 1, i + 1)
        if next_ch == quote or next_ch == "\\" then
          -- Valid escape: add the escaped character and skip both backslash and next char
          table.insert(current, next_ch)
          i = i + 2
        else
          -- Not a recognized escape: treat backslash as literal
          table.insert(current, ch)
          i = i + 1
        end
      elseif ch == quote then
        -- Closing quote found: exit quoted mode
        quote = nil
        i = i + 1
      else
        -- Regular character inside quoted string: add to current token
        table.insert(current, ch)
        i = i + 1
      end
    else
      -- Outside a quoted string: handle quote start, whitespace, and regular chars
      if ch == "\"" or ch == "'" then
        -- Opening quote: enter quoted mode
        quote = ch
        i = i + 1
      elseif ch:match("%s") then
        -- Whitespace: token boundary. Push current token and skip whitespace
        push()
        i = i + 1
      else
        -- Regular character: add to current token
        table.insert(current, ch)
        i = i + 1
      end
    end
  end

  -- Push any remaining accumulated characters as final token
  push()
  return tokens
end

local function is_safe_mod_token(token)
  if not token or token == "" then
    return false
  end

  -- Filter/expression tokens that must not be applied as modifications.
  if token == "(" or token == ")" then
    return false
  end
  local lower = token:lower()
  if lower == "and" or lower == "or" or lower == "xor" or lower == "!" then
    return false
  end

  -- Regex /.../ and substitution /from/to/(g) are ambiguous; skip.
  if token:match("^/.+/$") then
    return false
  end

  -- Skip relational expressions like "urgency>5" or "due<=eom".
  if token:match("[<>!=]=?") then
    return false
  end

  -- Tag add/remove is safe.
  if token:match("^[%+%-][%w_][%w_%-]*$") then
    return true
  end

  -- Attribute modification like project:Home, priority:H, due:tomorrow.
  -- Only accept plain attribute:value forms (no modifiers like .before/.not etc).
  -- Those are filter-specific and don't translate cleanly to a modification.
  if token:match("^[%w_]+:[^%s]+$") then
    local attr = token:match("^([%w_]+):")
    if attr and not attr:find("%.", 1, true) then
      return true
    end
  end

  return false
end

local function extract_safe_mods_from_filter(filter_str)
  local tokens = tokenize_tw_args(filter_str)
  local mods = {}
  for _, token in ipairs(tokens) do
    if is_safe_mod_token(token) then
      table.insert(mods, token)
    end
  end
  return mods
end

local function calculate_final_status(tasks)
  local pendingCount, activeCount, completedCount, deletedCount = 0, 0, 0, 0
  for _, task in ipairs(tasks) do
    if task.status == "pending" then
      if task["start"] ~= nil then
        activeCount = activeCount + 1
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
  end
  if completedCount == #tasks or (completedCount > 0 and (completedCount + deletedCount) == #tasks) then
    return "completed"
  end
  if deletedCount == #tasks then
    return "deleted"
  end
  return "active"
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
    local _, dependencies = task_mod.get_tasks_by(task["depends"])
    local new_status = calculate_final_status(dependencies)
    new_status, _ = findPair(M.status_map, nil, new_status)
    task_mod.modify_task_status(task.uuid, new_status)
    local line_number = find_pattern_line(task.uuid)
    if line_number ~= nil then
      M.toggle_task_status(nil, line_number, new_status)
    end
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
  local modified_line =
    string.gsub(current_line, M.status_pattern.lua, M.checkbox_prefix .. new_status .. M.checkbox_suffix)
  -- Set the modified line back to the buffer

  vim.api.nvim_buf_set_lines(0, line_number - 1, line_number, false, { modified_line })
  return new_status
end

-- task_cache: optional { [uuid] = task_data } lookup table from a prior bulk_export call.
-- When provided, no individual "task export" subprocess is spawned for existing tasks.
-- replace_desc: when true, push the buffer description to Taskwarrior (TWUpdateCurrent path).
--               when false/nil, pull TW's description into the buffer (TWSyncTasks path).
function M.add_or_sync_task(line, replace_desc, task_cache)
  local task = require("m_taskwarrior_d.task")
  local list_sb, _, md_status = string.match(line, M.checkbox_pattern.lua)
  local desc = string.gsub(line, M.checkbox_pattern.lua, "")
  local result
  local _, _, uuid = string.match(line, M.id_part_pattern.lua)
  if uuid == nil then
    -- New task: add it to Taskwarrior and annotate the line.
    uuid = task.add_task(desc)
    result = line:gsub("%s+$", "")
      .. (M.comment_prefix ~= "" and " " .. M.comment_prefix or M.comment_prefix)
      .. " $id{"
      .. uuid
      .. "}"
      .. (M.comment_suffix ~= "" and " " .. M.comment_suffix or M.comment_suffix)
    -- Newly added tasks already have the correct status from the `task add` call;
    -- no modify needed here.
  else
    desc = string.gsub(desc, M.id_part_pattern.lua, "")
    -- Use the cache if available; fall back to individual export only when needed.
    local cached = task_cache and task_cache[uuid]
    if cached == nil and task_cache ~= nil then
      -- UUID not in cache: task was not found by bulk_export (likely deleted).
      -- Re-create it.
      line = string.gsub(line, M.id_part_pattern.lua, "")
      uuid = task.add_task(desc)
      result = line:gsub("%s+$", "")
        .. (M.comment_prefix ~= "" and " " .. M.comment_prefix or M.comment_prefix)
        .. " $id{"
        .. uuid
        .. "}"
        .. (M.comment_suffix ~= "" and " " .. M.comment_suffix or M.comment_suffix)
    else
      -- No cache (called outside of sync_tasks) or task is in the cache.
      local new_task = cached or task.get_task_by(uuid, "task")
      if new_task == nil then
        -- Task not found in Taskwarrior at all: re-create it.
        line = string.gsub(line, M.id_part_pattern.lua, "")
        uuid = task.add_task(desc)
        result = line:gsub("%s+$", "")
          .. (M.comment_prefix ~= "" and " " .. M.comment_prefix or M.comment_prefix)
          .. " $id{"
          .. uuid
          .. "}"
          .. (M.comment_suffix ~= "" and " " .. M.comment_suffix or M.comment_suffix)
      else
        local active = new_task.status == "pending" and new_task["start"] ~= nil
        local tw_status_sym
        if not active then
          tw_status_sym, _ = findPair(M.status_map, nil, new_task.status)
        else
          tw_status_sym = ">"
        end
        uuid = new_task.uuid
        local spaces = count_leading_spaces(line)
        if replace_desc then
          -- TWUpdateCurrent path: buffer description → Taskwarrior.
          task.modify_task(uuid, desc)
          -- Only update status in TW when the buffer checkbox differs from TW's status.
          if md_status ~= tw_status_sym then
            task.modify_task_status(uuid, md_status)
          end
          result = string.rep(" ", spaces or 0)
            .. list_sb
            .. " "
            .. M.checkbox_prefix
            .. tw_status_sym
            .. M.checkbox_suffix
            .. " "
            .. M.trim(desc)
            .. (M.comment_prefix ~= "" and " " .. M.comment_prefix or M.comment_prefix)
            .. " $id{"
            .. new_task.uuid
            .. "}"
            .. (M.comment_suffix ~= "" and " " .. M.comment_suffix or M.comment_suffix)
        else
          -- TWSyncTasks path: Taskwarrior is source of truth.
          -- Pull TW's status/description into the buffer. No write-back needed.
          result = string.rep(" ", spaces or 0)
            .. list_sb
            .. " "
            .. M.checkbox_prefix
            .. tw_status_sym
            .. M.checkbox_suffix
            .. " "
            .. new_task.description
            .. (M.comment_prefix ~= "" and " " .. M.comment_prefix or M.comment_prefix)
            .. " $id{"
            .. new_task.uuid
            .. "}"
            .. (M.comment_suffix ~= "" and " " .. M.comment_suffix or M.comment_suffix)
        end
      end
    end
  end
  return result, uuid
end

function M.extract_uuid(line)
  if line == nil then
    return nil
  end
  local uuid_pattern = M.id_part_pattern.lua
  local _, conceal, uuid = string.match(line, uuid_pattern)
  return conceal, uuid
end

-- Returns (current_uuid, deps_list, child_count) where child_count is the number
-- of directly-indented child lines processed (so the caller can skip them).
-- task_cache: optional bulk_export lookup table.
function M.check_dependencies(line_number, task_cache)
  local current_line, _ = M.get_line(line_number)
  if current_line == nil then
    return nil, nil, 0
  end
  local _, current_uuid = M.extract_uuid(current_line)
  local current_number_of_spaces = count_leading_spaces(current_line)
  local deps = {}
  local count = 1
  local next_line = M.get_line(line_number + 1)
  if next_line == nil then
    return nil, nil, 0
  end
  local next_number_of_spaces = count_leading_spaces(next_line)
  if next_number_of_spaces == nil then
    return nil, nil, 0
  end
  local _, checkbox, _ = string.match(next_line, M.checkbox_pattern.lua)
  if checkbox == nil then
    return nil, nil, 0
  end
  while next_line ~= nil and checkbox ~= nil and current_number_of_spaces < next_number_of_spaces do
    local result, uuid = M.add_or_sync_task(next_line, nil, task_cache)
    vim.api.nvim_buf_set_lines(0, line_number + count - 1, line_number + count, false, { result })
    table.insert(deps, uuid)
    count = count + 1
    next_line = M.get_line(line_number + count)
    if next_line ~= nil then
      next_number_of_spaces = count_leading_spaces(next_line)
      _, checkbox, _ = string.match(next_line, M.checkbox_pattern.lua)
    end
  end
  return current_uuid, deps, count - 1
end

-- Compare two lists of UUIDs (order-insensitive) and return true if they differ.
local function deps_changed(new_deps, tw_depends)
  local tw_deps = tw_depends or {}
  if #new_deps ~= #tw_deps then return true end
  local set = {}
  for _, v in ipairs(tw_deps) do set[v] = true end
  for _, v in ipairs(new_deps) do
    if not set[v] then return true end
  end
  return false
end

-- Sync a single task line and its indented children.
-- Returns the number of child lines processed so the caller can skip them.
-- task_cache: optional bulk_export lookup table.
function M.sync_task(current_line, line_number, task_cache)
  local result, _ = M.add_or_sync_task(current_line, nil, task_cache)
  if result then
    vim.api.nvim_buf_set_lines(0, line_number - 1, line_number, false, { result })
  end
  local current_uuid, deps, child_count = M.check_dependencies(line_number, task_cache)
  if current_uuid ~= nil and deps and #deps > 0 then
    -- Only write deps back to Taskwarrior when they've actually changed.
    local cached = task_cache and task_cache[current_uuid]
    local tw_depends = cached and cached.depends or nil
    if deps_changed(deps, tw_depends) then
      require("m_taskwarrior_d.task").add_task_deps(current_uuid, deps)
    end
  end
  return child_count
end

function M.build_lookup(items)
  local lookup = {}
  for _, v in ipairs(items) do
    lookup[v.uuid] = v
  end
  return lookup
end

function M.build_hierarchy(item, visited, lookup)
  local dependencies = item.depends
  if not dependencies then
    return { uuid = item.uuid, desc = item.description, status = item.status, tags = item.tags }
  else
    local hierarchy = { uuid = item.uuid, desc = item.description, status = item.status, tags = item.tags }
    table.sort(dependencies, function(a, b)
      local dep_a = lookup[a]
      local dep_b = lookup[b]
      if not dep_a or not dep_b then
        return false
      end

      -- 4. Fallback: urgency
      if (dep_a.id ~= 0 and dep_b.id ~= 0) and dep_a.id ~= dep_b.id then
        return dep_a.id > dep_b.id
      end
      -- 2. Compare entry date (newest first or oldest first? assuming oldest first)
      if dep_a.entry ~= dep_b.entry then
        return dep_a.entry < dep_b.entry
      end

      -- 3. Tie-break: dependency chain check
      local a_depends_on_b = dep_a.depends and vim.tbl_contains(dep_a.depends, dep_b.uuid)
      local b_depends_on_a = dep_b.depends and vim.tbl_contains(dep_b.depends, dep_a.uuid)
      if a_depends_on_b then
        return true -- if b depends on a, a should come first
      else
        return false
      end
      -- 1. Check if they have dependencies
      local a_has_deps = dep_a.depends and #dep_a.depends > 0
      local b_has_deps = dep_b.depends and #dep_b.depends > 0
      if a_has_deps ~= b_has_deps then
        return a_has_deps
      end
    end)
    for _, dependency in ipairs(dependencies) do
      if not visited[dependency] then
        visited[dependency] = true
        local dependent_item = lookup[dependency]
        if dependent_item then
          local dependent_hierarchy = M.build_hierarchy(dependent_item, visited, lookup)
          table.insert(hierarchy, dependent_hierarchy)
        end
      end
    end
    return hierarchy
  end
end

function M.render_tasks(tasks, depth)
  depth = depth or 0
  local markdown = {}
  for _, task in ipairs(tasks) do
    local active = false
    if task.status == "pending" and task["start"] ~= nil then
      active = true
    end
    local new_task_status_sym
    if not active then
      new_task_status_sym, _ = findPair(require("m_taskwarrior_d.utils").status_map, nil, task.status)
    else
      new_task_status_sym = ">"
    end
    if task.desc:find("\n") then
      print(
        string.format(
          "The task %s has a newline character. In order to render the task, please consider to remove the newline in the task's description",
          task.uuid
        )
      )
    else
      table.insert(
        markdown,
        string.rep(" ", vim.opt_local.shiftwidth._value * depth)
          .. M.default_list_symbol
          .. " "
          .. M.checkbox_prefix
          .. new_task_status_sym
          .. M.checkbox_suffix
          .. " "
          .. task.desc
          .. (M.comment_prefix ~= "" and " " .. M.comment_prefix or M.comment_prefix)
          .. " $id{"
          .. task.uuid
          .. "}"
          .. (M.comment_suffix ~= "" and " " .. M.comment_suffix or M.comment_suffix)
      )
      if task[1] then
        local nested_tasks = M.render_tasks(task, depth + 1)
        for _, nested_task in ipairs(nested_tasks) do
          table.insert(markdown, nested_task)
        end
      end
    end
  end
  return markdown
end

-- Check whether a list of safe mod tokens is already reflected in an existing task.
-- Returns true if all mods are already present (no update needed).
local function task_has_mods(tw_task, mods)
  for _, token in ipairs(mods) do
    local attr, value = token:match("^([%w_]+):(.+)$")
    if attr then
      -- Normalise common attribute aliases.
      if attr == "proj" then attr = "project" end
      local tw_val = tw_task[attr]
      if tw_val == nil then
        return false
      end
      -- Taskwarrior values may be sub-project strings; do a prefix match.
      if tostring(tw_val) ~= value then
        return false
      end
    elseif token:match("^%+[%w_%-]+$") then
      local tag = token:sub(2)
      local tags = tw_task.tags or {}
      local found = false
      for _, t in ipairs(tags) do
        if t == tag then found = true; break end
      end
      if not found then return false end
    elseif token:match("^%-[%w_%-]+$") then
      -- Tag removal: if the tag is still present, we need to update.
      local tag = token:sub(2)
      local tags = tw_task.tags or {}
      for _, t in ipairs(tags) do
        if t == tag then return false end
      end
    end
  end
  return true
end

function M.apply_context_data(line, line_number, task_cache)
  local no_of_lines = vim.api.nvim_buf_line_count(0)
  if line_number == no_of_lines then
    return
  end
  local _, _, query = string.match(line, M["task_query_pattern"].lua)

  -- Taskwarrior filter strings can contain filter-only tokens (status filters,
  -- boolean logic, regex, etc.) that should never be passed to `task <uuid> mod`.
  -- Extract only tokens that are safe to apply as modifications.
  local mods = extract_safe_mods_from_filter(query)
  query = table.concat(mods, " ")
  local count = 1
  local uuid = nil
  local tasks = {}
  local next_line, next_line_number = M.get_line(line_number + count)
  _, uuid = M.extract_uuid(next_line)
  if uuid then
    table.insert(tasks, uuid)
  end
  local block_ended = true
  if #next_line == 0 or next_line == " " then
    block_ended = false
  end
  while not block_ended and next_line_number <= no_of_lines do
    count = count + 1
    next_line, next_line_number = M.get_line(line_number + count)
    if next_line_number == no_of_lines or #next_line == 0 or next_line == " " then
      block_ended = true
    end
    _, uuid = M.extract_uuid(next_line)
    if uuid then
      table.insert(tasks, uuid)
    end
  end
  local task = require("m_taskwarrior_d.task")
  for _, task_uuid in ipairs(tasks) do
    local cached = task_cache and task_cache[task_uuid]
    -- Skip the modify call if the task already has all the context attributes.
    if cached and task_has_mods(cached, mods) then
      -- Nothing to update.
    else
      local args = { "task", task_uuid, "mod" }
      task.append_tokens(args, query)
      task.execute_task_args(args)
    end
  end
end

function M.delete_scoped_tasks(line_number)
  local count = 1
  local start_line = nil
  local end_line = nil
  local no_of_lines = vim.api.nvim_buf_line_count(0)
  if line_number == no_of_lines then
    return
  end
  local next_line, next_line_number = M.get_line(line_number + count)
  if #next_line == 0 or next_line == " " then
    start_line = next_line_number
  else
    vim.api.nvim_buf_set_lines(0, line_number, line_number, false, { "" })
    return
  end
  while end_line == nil and next_line_number < no_of_lines do
    count = count + 1
    next_line, next_line_number = M.get_line(line_number + count)
    local list_sb, _, status = string.match(next_line, M.checkbox_pattern.lua)
    if #next_line > 0 and next_line ~= " " and list_sb == nil then
      end_line = next_line_number - 1
    end
  end
  if end_line == nil then
    end_line = no_of_lines
  end
  vim.api.nvim_buf_set_lines(0, start_line, end_line, false, {})
end

function M.parse_ISO8601_date(iso_date)
  local pattern = "(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)Z"
  local year, month, day, hour, min, sec = iso_date:match(pattern)

  return os.time({
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour),
    min = tonumber(min),
    sec = tonumber(sec),
  })
end

-- Fetch task data for a list of UUIDs using a single bulk Taskwarrior invocation,
-- then invoke callback(tasks) where tasks is a list of task tables (excluding
-- deleted/completed tasks).
local function get_task_data_async(uuids, callback)
  local lookup = M.task.bulk_export(uuids)
  local tasks = {}
  for _, task_data in pairs(lookup) do
    if task_data.status ~= "deleted" and task_data.status ~= "completed" then
      table.insert(tasks, task_data)
    end
  end
  callback(tasks)
end

function M.render_virtual_due_dates(start_line, end_line)
  -- 1. Setup/Defaults
  start_line = start_line or 0
  end_line = end_line or -1

  local lines = vim.api.nvim_buf_get_lines(0, start_line, end_line, false)
  local line_to_uuid = {}
  local all_uuids = {}

  -- Clear all existing marks first to avoid flickering
  vim.api.nvim_buf_clear_namespace(0, M.ns_due_id, start_line, end_line)

  -- 2. Collect all UUIDs and map them to line numbers (non-blocking)
  for i, line_content in ipairs(lines) do
    local _, uuid = M.extract_uuid(line_content)
    if uuid then
      -- Store the 0-indexed buffer line number (i + start_line - 1)
      line_to_uuid[uuid] = (i + start_line - 1)
      table.insert(all_uuids, uuid)
    end
  end

  -- Optimization: If no tasks, we're done.
  if #all_uuids == 0 then
    return
  end

  -- 3. Asynchronously fetch all task data (Major optimization)
  -- Replace get_task_data_async with your actual async function
  -- that calls Taskwarrior once for all tasks.
  get_task_data_async(all_uuids, function(tasks)
      -- This function runs *after* the Taskwarrior process completes,
      -- allowing the editor to remain responsive during the wait.

      -- Create a map for quick lookups: uuid -> task_data
      local task_data_map = {}
      for _, task in ipairs(tasks) do
          task_data_map[task.uuid] = task
      end

      -- 4. Process data and set extmarks (non-blocking)
      for uuid, line_idx in pairs(line_to_uuid) do
          local task_data = task_data_map[uuid]

          if task_data and (task_data.due or task_data.scheduled) then
              -- Move time calculation logic into a local function for clarity
              local function calculate_time_diff(task_data)
                  local target_time
                  local time_text = ""

                  if task_data.scheduled then
                      time_text = "Scheduled: "
                      target_time = M.parse_ISO8601_date(task_data.scheduled)
                  end

                  if task_data.due then
                      time_text = "Due: "
                      target_time = M.parse_ISO8601_date(task_data.due)
                  end

                  if not target_time then return end

                  local current_time = os.time()
                  local time_diff = os.difftime(target_time, current_time)

                  local days = math.floor(time_diff / (24 * 3600))
                  local hours = math.floor((time_diff % (24 * 3600)) / 3600)
                  local minutes = math.floor((time_diff % 3600) / 60)

                  local highlight_group
                  local display_text
                  if days > 0 then
                      display_text = string.format("%d days, %d hours left", days, hours)
                      highlight_group = "DueDate"
                  elseif days >=0 and hours >= 0 and minutes >= 0 then -- Due soon or within the next hour
                      display_text = string.format("%d hours, %d minutes left", hours, minutes)
                      highlight_group = "DueSoon"
                  else -- Overdue (time_diff is negative)
                      local abs_diff = -time_diff
                      local days_ago = math.floor(abs_diff / (24 * 3600))
                      local hours_ago = math.floor((abs_diff % (24 * 3600)) / 3600)
                      display_text = string.format("OVERDUE: %d days, %d hours ago", days_ago, hours_ago)
                      highlight_group = "DueOverdue" -- Assuming you define this highlight group
                  end
                  return { time_text .. display_text, highlight_group }
              end

              local text_tuple = calculate_time_diff(task_data)
              if text_tuple then
                  vim.api.nvim_buf_set_extmark(0, M.ns_due_id, line_idx, 0, {
                      virt_text = { text_tuple },
                      virt_text_pos = "eol",
                  })
              end
          end
      end
  end) -- End of M.task.get_task_data_async callback
end
return M
