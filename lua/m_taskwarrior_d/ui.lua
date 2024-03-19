local M = {}

function M.trigger_hover(contents, title)
  if title == nil then
    title = ''
  end
  local Popup = require("nui.popup")
  local event = require("nui.utils.autocmd").event
  local autocmd = require("nui.utils.autocmd")
  local max_width = 0
  for _, content in ipairs(contents) do
    max_width = math.max(max_width, #content)
  end
  local popup = Popup({
    enter = false,
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = title,
        top_align = "center",
      }
    },
    relative = "cursor",
    position = 0,
    size = {
      width = max_width + 1,
      height = #contents,
    },
  })

  -- mount/open the component
  local bufnr = vim.api.nvim_get_current_buf()
  autocmd.buf.define(bufnr, { event.CursorMoved, event.BufWinLeave }, function()
    popup:unmount()
  end, { once = true })
  popup:mount()

  vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, contents)
    vim.api.nvim_buf_set_keymap(popup.bufnr, "n", "q", "<Cmd>q<CR>", { silent = true })
  return popup
end

return M
