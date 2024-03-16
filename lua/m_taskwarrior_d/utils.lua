local M = {}

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

return M
