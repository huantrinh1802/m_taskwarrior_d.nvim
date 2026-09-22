-- Frontmatter task-note mode: one Markdown file = one Taskwarrior task,
-- identified/gated by a YAML frontmatter indicator key (frontmatter_indicator_key).
-- This is fully additive to the checkbox-line ($id{...}) workflow in utils.lua.
local M = {}

function M.set_config(opts)
  for k, v in pairs(opts) do
    M[k] = v
  end
end

local function escape_lua_pattern(str)
  return (str:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1"))
end

-- Returns yaml_text (frontmatter lines joined with "\n"), start_line, end_line
-- (0-indexed buffer line numbers of the opening/closing "---" fences) if the
-- buffer starts with a "---" fence and a closing one is found within a
-- bounded scan window. Returns nil (silently) if there's no opening fence,
-- or nil with a warning notification if the fence is opened but never closed.
function M.extract_frontmatter_block(bufnr)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    return nil
  end
  local first = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
  if first == nil or vim.trim(first) ~= "---" then
    return nil
  end

  local max_scan = math.min(200, line_count)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, max_scan, false)
  for i = 2, #lines do
    if vim.trim(lines[i]) == "---" then
      local yaml_lines = vim.api.nvim_buf_get_lines(bufnr, 1, i - 1, false)
      return table.concat(yaml_lines, "\n"), 0, i - 1
    end
  end

  vim.notify(
    "m_taskwarrior_d: frontmatter opened with '---' but no closing fence found within the first "
      .. max_scan
      .. " lines; skipping sync",
    vim.log.levels.WARN
  )
  return nil
end

-- Shells out to `yq -o=json` (mikefarah/yq) to convert the YAML frontmatter
-- block to JSON, then decodes it the same way task export output is decoded
-- elsewhere in the plugin. Returns table, nil on success or nil, err on failure.
function M.parse_yaml(yaml_text)
  if vim.fn.executable(M.yq_bin) == 0 then
    return nil, M.yq_bin .. " not found on $PATH"
  end
  if yaml_text == nil or #vim.trim(yaml_text) == 0 then
    return {}, nil
  end

  local obj = vim.system({ M.yq_bin, "-o=json" }, { text = true, stdin = yaml_text }):wait()
  if obj.code ~= 0 then
    return nil, obj.stderr
  end
  local ok, decoded = pcall(vim.json.decode, obj.stdout)
  if not ok then
    return nil, decoded
  end
  return decoded, nil
end

-- A file is only ever treated as a linked task note if this key is present
-- and strictly `true` -- arbitrary frontmatter on unrelated notes must never
-- trigger a sync.
function M.is_task_note(fm)
  if type(fm) ~= "table" then
    return false
  end
  return fm[M.frontmatter_indicator_key] == true
end

-- Task description source: frontmatter_title_key if present/non-empty, else
-- the filename minus extension.
function M.get_task_description(fm, bufnr)
  local title = fm[M.frontmatter_title_key]
  if type(title) == "string" and vim.trim(title) ~= "" then
    return title
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  return vim.fn.fnamemodify(name, ":t:r")
end

-- Scans the raw buffer lines (not yq's reformatted output) for `key:` within
-- [start_line, end_line) to get a byte-accurate 0-indexed line for a
-- surgical in-place replace/insert.
function M.find_key_line(bufnr, start_line, end_line, key)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line + 1, end_line, false)
  local pattern = "^%s*" .. escape_lua_pattern(key) .. "%s*:"
  for i, line in ipairs(lines) do
    if string.match(line, pattern) then
      return start_line + i
    end
  end
  return nil
end

-- Inserts (new task) or replaces (already had a stale/placeholder uuid key)
-- the uuid: line via a direct nvim_buf_set_lines edit. Deliberately does NOT
-- use `yq -i`, which re-serializes the whole document and risks reflowing or
-- reordering the user's existing frontmatter -- only this one line ever changes.
function M.write_uuid_back(bufnr, uuid, start_line, end_line)
  local existing_idx = M.find_key_line(bufnr, start_line, end_line, M.frontmatter_uuid_key)
  local new_line = M.frontmatter_uuid_key .. ": " .. uuid
  if existing_idx then
    vim.api.nvim_buf_set_lines(bufnr, existing_idx, existing_idx + 1, false, { new_line })
  else
    vim.api.nvim_buf_set_lines(bufnr, start_line + 1, start_line + 1, false, { new_line })
  end
end

-- Builds "key:value" (and "+tag" for a `tags` list) modification strings from
-- frontmatter, excluding the indicator/uuid/title keys. Any other list-valued
-- key has no clean Taskwarrior mapping and is skipped with a warning rather
-- than silently mis-formatting the `task modify` call.
function M.attrs_to_modify(fm)
  local kv_pairs = {}
  for key, value in pairs(fm) do
    if key ~= M.frontmatter_indicator_key and key ~= M.frontmatter_uuid_key and key ~= M.frontmatter_title_key then
      if key == "tags" and type(value) == "table" then
        for _, tag in ipairs(value) do
          table.insert(kv_pairs, "+" .. tostring(tag))
        end
      elseif type(value) == "table" then
        vim.notify(
          "m_taskwarrior_d: frontmatter key '" .. key .. "' is a list/table and has no Taskwarrior mapping; skipping",
          vim.log.levels.WARN
        )
      else
        table.insert(kv_pairs, key .. ":" .. tostring(value))
      end
    end
  end
  return kv_pairs
end

-- Orchestrates a full frontmatter sync for one buffer: extract -> parse ->
-- gate on is_task_note -> create-or-reuse the Taskwarrior task -> push
-- description + attributes. Frontmatter is authoritative (buffer wins) for
-- description, pushed on every sync, not just at creation. Returns the
-- task's uuid, or nil if the buffer isn't an opted-in task note.
function M.sync_note(bufnr)
  local fm_text, start_line, end_line = M.extract_frontmatter_block(bufnr)
  if fm_text == nil then
    return nil
  end

  local fm, err = M.parse_yaml(fm_text)
  if fm == nil then
    vim.notify("m_taskwarrior_d: frontmatter parse failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
    return nil
  end
  if not M.is_task_note(fm) then
    return nil
  end

  local task_mod = require("m_taskwarrior_d.task")
  local uuid = fm[M.frontmatter_uuid_key]
  local description = M.get_task_description(fm, bufnr)

  if uuid == nil or task_mod.get_task_by(uuid) == nil then
    uuid = task_mod.add_task(description)
    M.write_uuid_back(bufnr, uuid, start_line, end_line)
  else
    task_mod.modify_task_attrs(uuid, { "description:" .. description })
  end

  task_mod.modify_task_attrs(uuid, M.attrs_to_modify(fm))
  return uuid
end

return M
