local M = {}
M.task = require("m_taskwarrior_d.task")
M.treesitter = require("m_taskwarrior_d.treesitter")
M.utils = require("m_taskwarrior_d.utils")
M._concealTaskId = nil
M._config = {
  task_statuses = { " ", ">", "x", "~" },
  status_map = { [" "] = "pending", [">"] = "started", ["x"] = "completed", ["~"] = "deleted" },
  id_pattern = { vim = "\\x*-\\x*-\\x*-\\x*-\\x*", lua = "%x*-%x*-%x*-%x*-%x*" },
  list_pattern = { lua = "[%-%*%+]", vim = "[\\-\\*\\+]" },
  -- checkbox_pattern = { lua = "([%-%*%+]) (%[([%sx~%>])%])", vim = "([\\-\\*\\+]) (\\[([\\sx~>])\\])" },
  -- task_pattern = {
  --   lua = M.checkbox_pattern.lua .. " (.*) " .. M.id_part_pattern.lua,
  --   vim = M.checkbox_pattern.vim .. " (.*) " .. M.id_part_pattern.vim,
  -- },
}

function M.sync_tasks()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Get the lines in the buffer
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  -- Iterate through each line to get the number of leading spaces
  for i, line in ipairs(lines) do
    print(M._config.checkbox_pattern.lua)
    if string.match(line, M._config.checkbox_pattern.lua) then
      local result = M.utils.add_or_sync_task(line)
      if result then
        vim.api.nvim_buf_set_lines(bufnr, i - 1, i, false, { result })
      end
      local current_uuid, deps = M.utils.check_dependencies(i)
      if current_uuid ~= nil then
        M.task.add_task_deps(current_uuid, deps)
      end
    end
  end
end

function M.edit_task()
  local current_buffer = vim.api.nvim_get_current_buf()
  local current_line, current_line_number = M.utils.get_line()
  local conceal, uuid = M.utils.extract_uuid(current_line)
  local task_info = M.task.get_task_by(uuid)
  if task_info == nil then
    print("No task found")
    return
  end

  local Popup = require("nui.popup")
  local event = require("nui.utils.autocmd").event

  local popup = Popup({
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
    },
    position = "50%",
    size = {
      width = "80%",
      height = "60%",
    },
  })

  -- mount/open the component
  popup:mount()
  vim.cmd("term " .. "task " .. uuid .. " edit")
  vim.cmd("startinsert")
  popup:on(event.TermClose, function()
    local synced_result = M.utils.add_or_sync_task(current_line)
    vim.api.nvim_buf_set_lines(current_buffer, current_line_number - 1, current_line_number, false, { synced_result })
    popup:unmount()
  end)
end

function M.toggle_task()
  local current_line, line_number = M.utils.get_line()
  local _, uuid = M.utils.extract_uuid(current_line)
  if uuid == nil then
    current_line = M.utils.add_task(current_line)
  end
  local task = M.task.get_task_by(uuid)
  if task and task["depends"] ~= nil then
    print("This task has dependencies: " .. table.concat(task["depends"], ", "))
    return nil
  end
  local new_status = M.utils.toggle_task_status(current_line, line_number)
  _, uuid = M.utils.extract_uuid(current_line)
  if new_status ~= nil then
    M.task.modify_task_status(uuid, new_status)
    M.utils.update_related_tasks_statuses(uuid)
  end
end

function M.update_current_task()
  local current_line, line_number = M.utils.get_line()
  local result = M.utils.add_or_sync_task(current_line, true)
  vim.api.nvim_buf_set_lines(0, line_number - 1, line_number, false, { result })
end

function M.view_task()
  local current_line = vim.api.nvim_get_current_line()
  local conceal, uuid = M.extract_uuid(current_line)
  local task_info = M.task.get_task_by(uuid, "task")
  if task_info == nil then
    print("No task found")
    return
  end
  local md_table = {}
  for k, v in pairs(task_info) do
    if type(v) == "table" then
      for i, j in ipairs(v) do
        local row
        if i == 1 then
          row = k .. string.rep(" ", 15 - #k) .. " | " .. j
        else
          row = string.rep(" ", 15) .. " | " .. j
        end
        table.insert(md_table, row)
      end
    else
      local row = k .. string.rep(" ", 15 - #k) .. " | " .. v
      table.insert(md_table, row)
    end
    table.insert(md_table, string.rep("-", 16) .. "|" .. string.rep("-", 62 - 17))
  end

  local Popup = require("nui.popup")
  local event = require("nui.utils.autocmd").event
  local autocmd = require("nui.utils.autocmd")

  local popup = Popup({
    enter = false,
    focusable = true,
    border = {
      style = "rounded",
    },
    relative = "cursor",
    position = 0,
    size = {
      width = 62,
      height = #md_table,
    },
  })

  -- mount/open the component
  local bufnr = vim.api.nvim_get_current_buf()
  autocmd.buf.define(bufnr, { event.CursorMoved, event.BufEnter }, function()
    popup:unmount()
  end, { once = true })

  popup:mount()

  vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, md_table)
end

local function process_opts(opts)
  if opts ~= nil then
    for k, v in pairs(opts) do
      M._config[k] = v
    end
  end
  local status_pattern = M.utils.encode_patterns(table.concat(M._config.task_statuses, ""))
  M._config["status_pattern"] = {
    lua = "(%[(["..status_pattern.lua.."])%])",
    vim = "(\\[(["..status_pattern.vim.."])\\])",
  }
  M._config["checkbox_pattern"] = {
    lua = "(" .. M._config.list_pattern.lua .. ") "..M._config["status_pattern"].lua,
    vim = "(" .. M._config.list_pattern.vim .. ") "..M._config["status_pattern"].vim,
  }
  M._config["id_part_pattern"] = {
    vim = "(\\$id{" .. M._config.id_pattern.vim .. "})",
    lua = "(%$id{(" .. M._config.id_pattern.lua .. ")})",
  }
  M._config["task_pattern"] = {
    lua = M._config.checkbox_pattern.lua .. " (.*) " .. M._config.id_part_pattern.lua,
    vim = M._config.checkbox_pattern.vim .. " (.*) " .. M._config.id_part_pattern.vim,
  }
end

function M.setup(opts)
  process_opts(opts)
  M.utils.set_config(M._config)
  M.task.set_config(M._config)
  local conceal_group = vim.api.nvim_create_augroup("TWConceal", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    group = conceal_group,
    pattern = "*.md", -- Pattern to match Markdown files
    callback = function()
      -- Get the file type of the current buffer
      vim.opt.conceallevel = 2
      M._concealTaskId = vim.fn.matchadd("Conceal", "\\(\\$id{\\([0-9a-fA-F\\-]\\+\\)}\\)", 0, -1, { conceal = "" })
      vim.api.nvim_exec([[hi Conceal ctermfg=109 guifg=#83a598 ctermbg=NONE guibg=NONE]], false)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufLeave" }, {
    group = conceal_group,
    pattern = "*.md", -- Pattern to match Markdown files
    callback = function()
      -- Get the file type of the current buffer
      vim.opt.conceallevel = 0
      vim.api.nvim_exec([[hi Conceal ctermfg=109 guifg=NONE ctermbg=NONE guibg=NONE]], false)
    end,
  })

  vim.api.nvim_create_user_command("TWToggle", function()
    M.toggle_task()
  end, {})
  vim.api.nvim_create_user_command("TWSyncTasks", function()
    M.sync_tasks()
  end, {})
  vim.api.nvim_create_user_command("TWUpdateCurrent", function()
    M.update_current_task()
  end, {})
  vim.api.nvim_create_user_command("TWEditTask", function()
    M.edit_task()
  end, {})
  vim.api.nvim_create_user_command("TWView", function()
    M.view_task()
  end, {})
end

return M
