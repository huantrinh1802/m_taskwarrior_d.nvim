local M = {}
M.task = require("m_taskwarrior_d.task")
M.treesitter = require("m_taskwarrior_d.treesitter")
M.utils = require("m_taskwarrior_d.utils")
M.ui = require("m_taskwarrior_d.ui")
M._concealTaskId = nil
M.current_winid = nil
M._config = {
  task_statuses = { " ", ">", "x", "~" },
  status_map = { [" "] = "pending", [">"] = "started", ["x"] = "completed", ["~"] = "deleted" },
  id_pattern = { vim = "\\x*-\\x*-\\x*-\\x*-\\x*", lua = "%x*-%x*-%x*-%x*-%x*" },
  list_pattern = { lua = "[%-%*%+]", vim = "[\\-\\*\\+]" },
  task_whitelist_path = { },
  view_task_config = { total_width = 62, head_width = 15 },
  fields_order = { "project", "description", "urgency", "status", "tags", "annotations" }

}

function M.sync_tasks(start_position, end_position)
  if start_position == nil then
    start_position = 1
  end
  if end_position == nil then
    end_position = vim.api.nvim_buf_line_count(0)
  end
  local headers = {}
  -- Iterate through each line to get the number of leading spaces
  for line_number = start_position, end_position do
    local current_line, _ = M.utils.get_line(line_number)
    if string.match(current_line, M._config.checkbox_pattern.lua) then
      M.utils.sync_task(current_line, line_number)
    end
    if string.match(current_line, M._config.task_query_pattern.lua) then
      table.insert(headers, { line = current_line, line_number = line_number })
    end
  end
  for _, header in pairs(headers) do
    M.utils.apply_context_data(header.line, header.line_number)
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
    local synced_result, _ = M.utils.add_or_sync_task(current_line)
    vim.api.nvim_buf_set_lines(current_buffer, current_line_number - 1, current_line_number, false, { synced_result })
    popup:unmount()
  end)
end

function M.toggle_task()
  local current_line, line_number = M.utils.get_line()
  local _, uuid = M.utils.extract_uuid(current_line)
  if uuid ~= nil then
    local task = M.task.get_task_by(uuid, "task")
    if task and task["depends"] ~= nil then
      print("This task has dependencies: " .. table.concat(task["depends"], ", "))
      return nil
    end
  end
  local new_status = M.utils.toggle_task_status(current_line, line_number)
  _, uuid = M.utils.extract_uuid(current_line)
  if new_status ~= nil and uuid ~= nil then
    M.task.modify_task_status(uuid, new_status)
    M.utils.update_related_tasks_statuses(uuid)
  end
end

function M.update_current_task()
  local current_line, line_number = M.utils.get_line()
  local result, _ = M.utils.add_or_sync_task(current_line, true)
  vim.api.nvim_buf_set_lines(0, line_number - 1, line_number, false, { result })
end

local function find_next_index(item, inserted_list, table)
  if inserted_list[item] == nil then
    return nil
  end
  local loc = 1
  for _, v in ipairs(M._config.fields_order) do
    if inserted_list[v] ~= false then
      loc = loc + inserted_list[v]
    end
    if v == item then
      return loc
    end
  end
  return nil
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
  local fields_has_date = { "start", "due", "end", "wait", "until", "scheduled", "entry", "modified" }
  local inserted = {}
  for _, v in ipairs(M._config.fields_order) do
    inserted[v] = false
  end
  for k, v in pairs(task_info) do
    local loc = find_next_index(k, inserted, md_table) or #md_table + 1 
    local number_of_lines = 0
    if type(v) == "table" then
      for i, j in ipairs(v) do
        if i ~= 1 then
          loc = loc + 1
        end
        local row
        if type(j) == "table" then
          j = j.description
        end
        local head = ""
        if i == 1 then
          head = k .. string.rep(" ", M._config.view_task_config.head_width - #k)
        else
          head = string.rep(" ", M._config.view_task_config.head_width)
        end
        if #j > M._config.view_task_config.total_width - M._config.view_task_config.head_width - 5 then
          row = head
            .. " | - "
            .. j:sub(1, M._config.view_task_config.total_width - M._config.view_task_config.head_width - 5)
          row = row:gsub("$%s+", "")
          table.insert(md_table, loc, row)
          loc = loc + 1
          number_of_lines = number_of_lines + 1
          head = string.rep(" ", M._config.view_task_config.head_width)
          row = nil
          row = head
            .. " |"
            .. j:sub(M._config.view_task_config.total_width - M._config.view_task_config.head_width - 4)
        else
          row = head .. " | - " .. j
        end
        if row ~= nil then
          table.insert(md_table, loc, row)
        end
        number_of_lines = number_of_lines + 1
      end
    else
      if M.utils.contains(fields_has_date, k) then
        local local_time = M.utils.convert_timestamp_utc_local(v)
        v = os.date("%Y-%m-%d %H:%M", os.time(local_time))
      end
      local row = nil
      local head = k .. string.rep(" ", M._config.view_task_config.head_width - #k)
      if
        type(v) == "string" and #v > M._config.view_task_config.total_width - M._config.view_task_config.head_width - 3
      then
        row = head
          .. " | "
          .. v:sub(1, M._config.view_task_config.total_width - M._config.view_task_config.head_width - 3)
        row = row:gsub("$%s+", "")
        table.insert(md_table, loc, row)
        loc = loc + 1
        number_of_lines = number_of_lines + 1
        head = string.rep(" ", M._config.view_task_config.head_width)
        row = head .. " |" .. v:sub(M._config.view_task_config.total_width - M._config.view_task_config.head_width - 2)
      else
        row = head .. " | " .. v
      end
      table.insert(md_table, loc, row)
      number_of_lines = number_of_lines + 1
      inserted[k] = number_of_lines + 1
    end
    table.insert(
      md_table,
      loc + 1,
      string.rep("-", M._config.view_task_config.head_width + 1)
        .. "|--"
        .. string.rep("-", M._config.view_task_config.total_width - M._config.view_task_config.head_width)
    )
  end
  local popup = M.ui.trigger_hover(md_table, "Task " .. uuid)
  vim.api.nvim_buf_set_option(popup.bufnr, "filetype", "markdown")
  M.current_winid = popup.winid
  local event = require("nui.utils.autocmd").event
  popup:on(event.BufLeave, function()
    M.current_winid = nil
  end)
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
    table.insert(result, #result, string.rep("-", #result[1]))
    local popup = M.ui.trigger_hover(result)
    M.current_winid = popup.winid
    local event = require("nui.utils.autocmd").event
    popup:on(event.BufLeave, function()
      M.current_winid = nil
    end)
  end
end

function M.run_task_bulk(args)
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
    -- local _, result = M.task.execute_taskwarrior_command(command, true)
    -- if #result == 0 then
    --   print("No task found")
    --   return
    -- end
    local task_commands_not_to_display = { "add", "mod", "del", "purge" }
    local good_command = false
    local command = table.concat(args, " ")
    for _, keyword in ipairs(task_commands_not_to_display) do
      if string.find(command, keyword) then
        good_command = true
      end
    end
    if good_command then
      local start_line = vim.fn.line("'<") -- Get the start line of the selection
      local end_line = vim.fn.line("'>") -- Get the end line of the selection
      local results = {}
      for line_num = start_line, end_line do
        local current_line, _ = M.utils.get_line(line_num)
        local _, uuid = M.utils.extract_uuid(current_line)
        if uuid ~= nil then
          local _, result = M.task.execute_taskwarrior_command("task rc.confirmation=off " .. uuid .. " " .. command)
          table.insert(results, result .. "\n")
        end
      end
      for _, result in ipairs(results) do
        print(result)
      end
    end
  end
end

local function load_json_file(filename)
  local file = io.open(filename, "r")
  if file then
    local content = file:read("*all")
    file:close()
    return vim.json.decode(content)
  else
    return nil
  end
end

function M.view_saved_queries()
  local filename = vim.fn.stdpath("data") .. "/m_taskwarrior_d.json"
  local queries = load_json_file(filename)
  if queries == nil then
    print("No saved queries found")
    return
  end
  local Popup = require("nui.popup")
  local event = require("nui.utils.autocmd").event

  local popup = Popup({
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = "Saved queries",
        top_align = "center",
      },
    },
    win_options = {
      number = true,
    },
    position = "50%",
    size = {
      width = "60%",
      height = "50%",
    },
  })
  local saved_queries = {}
  for _, query in ipairs(queries.saved_queries.data) do
    table.insert(
      saved_queries,
      query.name .. string.rep(" ", queries.saved_queries.name_max_length - #query.name) .. " | " .. query.query
    )
  end
  -- mount/open the component
  popup:mount()
  M.current_winid = popup.winid
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, saved_queries)
  vim.api.nvim_buf_set_name(popup.bufnr, "m_taskwarrior_d_saved_queries")
  vim.api.nvim_buf_set_option(popup.bufnr, "filetype", "taskwarrior")
  vim.api.nvim_buf_set_option(popup.bufnr, "buftype", "acwrite")
  vim.api.nvim_buf_set_option(popup.bufnr, "bufhidden", "delete")
  vim.api.nvim_buf_set_keymap(popup.bufnr, "n", "q", "<Cmd>q<CR>", { silent = true })
  vim.cmd(string.format("autocmd BufModifiedSet <buffer=%s> set nomodified", popup.bufnr))
  popup:on(event.BufWriteCmd, function()
    local lines = vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false)
    local new_saved_queries = {}
    local name_max_length = 0
    for _, line in ipairs(lines) do
      local name, query = string.match(line, "^([^|]*)|(.*)")
      name = M.utils.trim(name)
      query = M.utils.trim(query)
      if #name > name_max_length then
        name_max_length = #name
      end
      table.insert(new_saved_queries, { name = name, query = query })
    end
    queries.saved_queries.data = new_saved_queries
    queries.saved_queries.name_max_length = name_max_length
    local file = io.open(filename, "w")
    if file ~= nil then
      if queries ~= nil then
        file:write(vim.json.encode(queries))
      end
      file:close()
    end
    M.current_winid = nil
    popup:unmount()
  end)

  popup:on(event.BufLeave, function()
    M.current_winid = nil
    popup:unmount()
  end)
end

function M.start_scratch(query)
  local Split = require("nui.split")

  local event = require("nui.utils.autocmd").event
  local split = Split({
    enter = true,
    relative = "editor",
    -- win_options = {
    --   number = true,
    -- },
    position = "right",
    size = "33%",
    -- buf_options = {
    --   filetype = "markdown",
    --   buftype = "acwrite",
    --   bufhidden = "delete",
    -- },
  })
  if M.scratch then
    M.scratch:unmount()
  end
  split:mount()
  M.scratch = split
  vim.api.nvim_buf_set_option(split.bufnr, "buftype", "acwrite")
  vim.api.nvim_buf_set_option(split.bufnr, "bufhidden", "delete")
  vim.api.nvim_buf_set_keymap(split.bufnr, "n", "q", "<Cmd>q<CR>", { silent = true })
  vim.cmd(string.format("autocmd BufModifiedSet <buffer=%s> set nomodified noswapfile", split.bufnr))
  vim.cmd("edit " .. vim.fn.stdpath("data") .. "/m_taskwarrior_d.md")
  vim.api.nvim_buf_set_lines(split.bufnr, 0, -1, false, { "" })
  vim.api.nvim_buf_set_lines(split.bufnr, 0, -1, false, { "# Task $query{" .. query .. "}" })
  vim.cmd("TWQueryTasks")
end

function M.toggle_saved_queries(type)
  local filename = vim.fn.stdpath("data") .. "/m_taskwarrior_d.json"
  local save_file = load_json_file(filename)
  local Menu = require("nui.menu")
  local lines = {}
  if save_file and save_file["saved_queries"] then
    for _, query in ipairs(save_file.saved_queries.data) do
      table.insert(lines, Menu.item(query.name, { query = query.query }))
    end
    local menu = Menu({
      position = "50%",
      size = {
        width = 40,
        height = 10,
      },
      border = {
        style = "single",
        text = {
          top = "TaskWarrior Queries",
          top_align = "center",
        },
      },
      win_options = {
        winhighlight = "Normal:Normal,FloatBorder:Normal",
      },
    }, {
      lines = lines,
      keymap = {
        focus_next = { "j", "<Down>", "<Tab>" },
        focus_prev = { "k", "<Up>", "<S-Tab>" },
        close = { "q", "<Esc>", "<C-c>" },
        submit = { "<CR>", "<Space>" },
      },
      on_submit = function(item)
        if type == "default" or type == nil then
          local query = item.query:gsub("|", " ")
          M.run_task({ query })
        elseif type == "split" then
          M.start_scratch(item.query)
        end
      end,
    })
    menu:mount()
  end
end

function M.query_tasks()
  local current_line, line_number = M.utils.get_line()
  local _, query, report = string.match(current_line, M._config["task_query_pattern"].lua)
  if query == nil then
    print("No query found in current line. Please go to the line contains ${}")
    return
  end
  M.utils.delete_scoped_tasks(line_number)
  local _, result = M.task.execute_taskwarrior_command("task " .. query .. " -TEMPLATE export " .. report, true)
  if result == nil then
    print("No results")
    return
  end
  local tasks = vim.fn.json_decode(result)
  local visited = {}
  local processed_tasks = {}
  local final = {}
  if tasks == nil then
    print("No results")
    return
  end
  for _, item in ipairs(tasks) do
    local hierarchy = M.utils.build_hierarchy(item, visited, tasks)
    table.insert(processed_tasks, hierarchy)
  end
  local current_nested = 1
  for _, task in ipairs(processed_tasks) do
    if not visited[task["uuid"]] then
      if task[1] then
        table.insert(final, current_nested, task)
        current_nested = current_nested + 1
      else
        table.insert(final, task)
      end
    end
  end
  local markdown = M.utils.render_tasks(final)
  table.insert(markdown, "")
  local no_of_lines = vim.api.nvim_buf_line_count(0)
  if no_of_lines == line_number then
    vim.api.nvim_buf_set_lines(0, no_of_lines, no_of_lines, false, { "" })
  end
  vim.api.nvim_buf_set_lines(0, line_number + 1, line_number + 1, false, markdown)
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
  M._config["task_query_pattern"] = {
    vim = "(\\$query{([^\\|]*)|*([^}]\\*)})",
    lua = "(%$query{([^%|]*)|*([^}]*)})",
  }
end

local function create_save_file_if_not_exist()
  local filename = vim.fn.stdpath("data") .. "/m_taskwarrior_d.json"
  local save_file = { saved_queries = { name_max_length = 0, data = {} } }
  if vim.fn.filereadable(filename) == 0 then
    local file = io.open(filename, "w")
    if file ~= nil then
      file:write(vim.json.encode(save_file))
      file:close()
    end
  end
end

function M.setup(opts)
  create_save_file_if_not_exist()
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
      M._concealTaskQuery = vim.fn.matchadd("Conceal", "\\$query{[^\\}]\\+}", 0, -1, { conceal = "󰡦" })
      vim.api.nvim_exec([[hi Conceal ctermfg=109 guifg=#83a598 ctermbg=NONE guibg=NONE]], false)
    end,
  })

  vim.api.nvim_create_user_command("TWToggle", function()
    M.toggle_task()
  end, {})
  vim.api.nvim_create_user_command("TWSyncCurrent", function()
    local current_line, line_number = M.utils.get_line()
    M.utils.sync_task(current_line, line_number)
  end, {})
  -- Should rename to TWSyncAll
  vim.api.nvim_create_user_command("TWSyncTasks", function()
    M.sync_tasks()
  end, {})
  vim.api.nvim_create_user_command("TWSyncBulk", function()
    local start_line = vim.fn.line("'<") -- Get the start line of the selection
    local end_line = vim.fn.line("'>") -- Get the end line of the selection
    M.sync_tasks(start_line, end_line)
  end, { range = true })
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
  vim.api.nvim_create_user_command("TWFocusFloat", function()
    if M.current_winid ~= nil then
      vim.api.nvim_set_current_win(M.current_winid)
    end
  end, {})
  vim.api.nvim_create_user_command("TWEditSavedQueries", function()
    M.view_saved_queries()
  end, {})
  vim.api.nvim_create_user_command("TWSavedQueries", function()
    M.toggle_saved_queries()
  end, {})
  vim.api.nvim_create_user_command("TWRunBulk", function(args)
    M.run_task_bulk(args.fargs)
  end, { nargs = "*", range = true })
  vim.api.nvim_create_user_command("TWQueryTasks", function()
    M.query_tasks()
  end, {})
    vim.api.nvim_create_user_command("TWTaskScratch", function()
    M.toggle_saved_queries('split')
  end, {})
  vim.api.nvim_create_user_command("TWScratchShow", function()
    if require("m_taskwarrior_d").scratch then
      require("m_taskwarrior_d").scratch:show()
    else
      print("No scratch window")
    end
  end, {})
  vim.api.nvim_create_user_command("TWScratchHide", function()
    if require("m_taskwarrior_d").scratch then
      require("m_taskwarrior_d").scratch:hide()
    else
      print("No scratch window")
    end
  end, {})

end

return M
