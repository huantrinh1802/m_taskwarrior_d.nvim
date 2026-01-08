local M = { _config = {} }

function M.set_config(opts)
  for k, v in pairs(opts) do
    M._config[k] = v
  end
end

function M.trigger_hover(contents, title)
  if title == nil then
    title = ""
  end
  local Popup = require("nui.popup")
  local event = require("nui.utils.autocmd").event
  local autocmd = require("nui.utils.autocmd")
  local max_width = 0
  for _, content in ipairs(contents) do
    max_width = math.max(max_width, #content)
  end
  local popup = Popup({
    enter = true,
    focusable = true,
    border = {
      style = "rounded",
      text = {
        top = title,
        top_align = "center",
      },
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
  autocmd.buf.define(bufnr, { event.BufWinLeave }, function()
    popup:unmount()
  end, { once = true })
  popup:mount()

  vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, contents)
  for _, key in ipairs(M._config.close_floating_window) do
    vim.api.nvim_buf_set_keymap(popup.bufnr, "n", key, "<Cmd>q<CR>", { silent = true })
  end
  return popup
end

function M.prompt_or_run(opts)
  local args = opts.args
  if args ~= nil and args ~= "" then
    return opts.run(args)
  end

  local Input = require("nui.input")
  local input = Input({
    relative = "cursor",
    position = 0,
    size = { width = opts.width or 100 },
    border = {
      style = "single",
      text = {
        top = opts.title or "",
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:Normal",
    },
  }, {
    prompt = opts.prompt or "",
    default_value = opts.default_value or "",
    on_submit = function(value)
      if value == nil or value == "" then
        return
      end
      opts.run(value)
    end,
  })

  input:mount()
end

return M
