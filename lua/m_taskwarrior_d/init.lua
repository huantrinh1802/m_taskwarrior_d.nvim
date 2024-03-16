local M = {}
M.ns = vim.api.nvim_create_namespace("m_taskwarrior_d")
M.utils = require("m_taskwarrior_d.utils")
M.task = require("m_taskwarrior_d.task")
M._concealTaskId = nil

local function extract_uuid(line)
  local uuid_pattern = "($id@(.*)@)"
  local conceal, uuid = string.match(line, uuid_pattern)
  return conceal, uuid
end

function M.convert_tasks()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Get the lines in the buffer
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Iterate through each line to get the number of leading spaces

  local task_pattern = "[%-%*%+] %[%s%]"
  local uuid_group_pattern = "@[0-9a-fA-F%-]+@"
  local uuid_pattern = "($id@(.*)@)"
  for i, line in ipairs(lines) do
    if string.match(line, task_pattern) then
      local result = string.gsub(line, task_pattern, "")
      local conceal, uuid = string.match(line, uuid_pattern)
      if uuid == nil then
        lines[i] = line:gsub("%s+$", "") .. " $id@" .. M.task.add_task(result) .. "@"
      else
        if M.task.get_task_by(uuid) == nil then
          result = string.gsub(result, uuid_pattern, "")
          line = string.gsub(line, uuid_pattern, "")
          lines[i] = line:gsub("%s+$", "") .. " $id@" .. M.task.add_task(result) .. "@"
        end
      end
    end
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

function M.display_hover_text()
  local current_line = vim.api.nvim_get_current_line()
  local conceal, uuid = extract_uuid(current_line)
  local task_info = M.task.get_task_by(uuid, "task")
  if task_info == nil then
    print("No task found")
    return
  end
  local tableString = "{"
  for k, v in pairs(task_info) do
    if type(k) == "number" then
      tableString = tableString .. v .. ","
    else
      tableString = tableString .. k .. " = " .. v .. ","
    end
  end
  tableString = tableString:sub(1, -2) -- Remove the last comma
  tableString = tableString .. "}"
  print(type(tableString))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, { tableString })
  local opts = { relative = "cursor", width = 50, height = 10, col = 0, row = 0, border = "rounded" }
  local win = vim.api.nvim_open_win(buf, true, opts)
  -- vim.api.nvim_set_option_value("winhl", "Normal:MyHighlight", { win = win })
end
-- Attach the function to BufEnter autocmd to ensure it's applied on buffer enter
-- vim.api.nvim_exec([[
-- augroup Concealer
--     autocmd!
--     autocmd BufEnter * lua require('m_taskwarrior_d').add_concealer(vim.fn.bufnr())
-- augroup END
-- ]], false)
function M.edit_task()
  local current_line = vim.api.nvim_get_current_line()
  local conceal, uuid = extract_uuid(current_line)
  local task_info = M.task.get_task_by(uuid)
  if task_info == nil then
    print("No task found")
    return
  end
  local Terminal = require("toggleterm.terminal").Terminal
  local taskwarrior = Terminal:new({
    cmd = 'task '..uuid..' edit',
    close_on_exit = true,
    direction="float"
  })
  taskwarrior:toggle()
end

vim.api.nvim_set_keymap("n","<leader>te", "<cmd>lua require'm_taskwarrior_d'.edit_task()<cr>",{ noremap = true, silent = true })
function M.setup(opts)
  -- local current_buffer = vim.api.nvim_get_current_buf()
  --
  -- -- Get the file type of the current buffer
  -- local filetype = vim.api.nvim_buf_get_option(current_buffer, "filetype")
  -- print(filetype)
  -- if filetype == "markdown" then
  --   -- M.convert_tasks()
  --   local pattern = "$id{.*}"
  --   vim.fn.matchadd("Conceal", pattern, 0, -1, { conceal = "" })
  --   vim.wo.conceallevel = 2
  -- endif vim.bo.filetype == 'markdown' then
  -- local pattern = "$id{.*}"
  -- local match_id = vim.api.nvim_buf_set_extmark(0, M.ns, 2, 5, {
  --   virt_text = { { "█", "Conceal" } },
  --   virt_text_pos = "overlay",
  --   hl_eol = true
  -- })
  --
  -- -- Check if match_id is a valid number
  -- if type(match_id) ~= "number" or match_id == -1 then
  --   print("Failed to add concealer for pattern: " .. pattern)
  -- end
  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    pattern = "*", -- Pattern to match Markdown files
    callback = function()
      local current_buffer = vim.api.nvim_get_current_buf()

      -- Get the file type of the current buffer
      local filetype = vim.api.nvim_buf_get_option(current_buffer, "filetype")
      if filetype == "markdown" then
        vim.opt.conceallevel = 2
        M._concealTaskId = vim.fn.matchadd("Conceal", "\\$id@.*@", 0, -1, { conceal = "" })
        vim.api.nvim_exec([[hi Conceal ctermfg=109 guifg=#83a598 ctermbg=NONE guibg=NONE]], false)
      else
        if M._concealTaskId ~= nil then
          vim.opt.conceallevel = 0
          local status, error = pcall(function()
            vim.fn.matchdelete(M._concealTaskId)
          end)
        end
      end
    end,
  })
end
return M
