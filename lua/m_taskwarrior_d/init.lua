local M = {}
M.task = require("m_taskwarrior_d.task")
M.treesitter = require("m_taskwarrior_d.treesitter")
M.utils = require("m_taskwarrior_d.utils")
M.ui = require("m_taskwarrior_d.ui")
M._concealTaskId = nil
M._config = {
  task_statuses = { " ", ">", "x", "~" },
  status_map = { [" "] = "pending", [">"] = "started", ["x"] = "completed", ["~"] = "deleted" },
  id_pattern = { vim = "\\x*-\\x*-\\x*-\\x*-\\x*", lua = "%x*-%x*-%x*-%x*-%x*" },
  list_pattern = { lua = "[%-%*%+]", vim = "[\\-\\*\\+]" },
}

function M.sync_tasks()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Get the lines in the buffer
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  -- Iterate through each line to get the number of leading spaces
  for i, line in ipairs(lines) do
    if string.match(line, M._config.checkbox_pattern.lua) then
      M.utils.sync_task(line, i)
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
  local conceal, uuid = M.utils.extract_uuid(current_line)
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
  M.ui.trigger_hover(md_table)
end

function M.run_with_current()
  local current_line, line_number = M.utils.get_line()
  local _, uuid = M.utils.extract_uuid(current_line)
  local Input = require("nui.input")
  local input = Input({
    relative = "cursor",
    position = 0,
    size = {
      width = 100,
    },
    border = {
      style = "single",
      text = {
        top = "Run task with " .. uuid,
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:Normal",
    },
  }, {
    prompt = "",
    default_value = "",
    on_submit = function(value)
      M.task.execute_taskwarrior_command("task " .. uuid .. " " .. value, nil, true)
      M.utils.sync_task(current_line, line_number)
    end,
  })
  input:mount()
end

local function split_by_newline(input)
  local lines = {}
  for line in input:gmatch("[^\n]+") do
    table.insert(lines, line)
  end
  table.insert(lines, #lines, string.rep("-", #lines[1]))
  return lines
end

function M.run_task(args)
  local command = "task " .. table.concat(args, " ")
  if #args == 0 then
    local Input = require("nui.input")
    local input = Input({
      relative = "cursor",
      position = 0,
      size = {
        width = 100,
      },
      border = {
        style = "single",
        text = {
          top = "Run task",
          top_align = "center",
        },
      },
      win_options = {
        winhighlight = "Normal:Normal,FloatBorder:Normal",
      },
    }, {
      on_submit = function(value)
        M.run_task({ value })
      end,
    })
    input:mount()
  else
    local _, result = M.task.execute_taskwarrior_command(command, true)
    if #result == 0 then
      print("No task found")
      return
    end
    local task_commands_not_to_display = { "add", "mod", "del", "purge" }
    for _, keyword in ipairs(task_commands_not_to_display) do
      if string.find(command, keyword) then
        print(result)
        return
      end
    end
    result = split_by_newline(result)
    M.ui.trigger_hover(result)
  end
end

local function process_opts(opts)
  if opts ~= nil then
    for k, v in pairs(opts) do
      M._config[k] = v
    end
  end
  local status_pattern = M.utils.encode_patterns(table.concat(M._config.task_statuses, ""))
  M._config["status_pattern"] = {
    lua = "(%[([" .. status_pattern.lua .. "])%])",
    vim = "(\\[([" .. status_pattern.vim .. "])\\])",
  }
  M._config["checkbox_pattern"] = {
    lua = "(" .. M._config.list_pattern.lua .. ") " .. M._config["status_pattern"].lua,
    vim = "(" .. M._config.list_pattern.vim .. ") " .. M._config["status_pattern"].vim,
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
  vim.api.nvim_create_user_command("TWSyncCurrent", function()
    local current_line, line_number = M.utils.get_line()
    M.utils.sync_task(current_line, line_number)
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
  vim.api.nvim_create_user_command("TWRunWithCurrent", function()
    M.run_with_current()
  end, {})
  vim.api.nvim_create_user_command("TWRun", function(args)
    M.run_task(args.fargs)
  end, { nargs = "*" })
end

return M
