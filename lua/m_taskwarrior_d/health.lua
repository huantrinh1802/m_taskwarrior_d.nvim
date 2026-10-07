-- :checkhealth m_taskwarrior_d
local M = {}

local health = vim.health

function M.check()
  health.start("m_taskwarrior_d: Neovim")
  if vim.fn.has("nvim-0.10") == 1 then
    local v = vim.version()
    health.ok(string.format("Neovim %d.%d.%d", v.major, v.minor, v.patch))
  else
    health.error("Neovim 0.10+ is required (vim.system, vim.json)", { "Upgrade Neovim" })
  end

  health.start("m_taskwarrior_d: Taskwarrior")
  if vim.fn.executable("task") ~= 1 then
    health.error("`task` not found on $PATH; every command and the BufEnter autocmd will fail", {
      "Install Taskwarrior: https://taskwarrior.org/download/",
    })
  else
    local ok, obj = pcall(function()
      return vim.system({ "task", "--version" }, { text = true }):wait(5000)
    end)
    local version = ok and obj.code == 0 and vim.trim(obj.stdout or "") or nil
    if not version or version == "" then
      health.error("`task --version` failed: " .. (ok and vim.trim(obj.stderr or "") or tostring(obj)))
    elseif tonumber(version:match("^(%d+)")) >= 3 then
      health.warn("Taskwarrior " .. version .. " found; the plugin is developed against Taskwarrior 2.x")
    else
      health.ok("Taskwarrior " .. version)
    end

    if version then
      -- A real read against the configured database catches a bad TASKRC or
      -- data.location before the first sync does.
      local count = vim.system({ "task", "rc.confirmation=off", "rc.verbose=nothing", "count" }, { text = true })
        :wait(5000)
      if count.code == 0 then
        health.ok("Task database readable (" .. vim.trim(count.stdout or "") .. " tasks)")
      else
        health.error("`task count` failed: " .. vim.trim(count.stderr or ""), {
          "Check $TASKRC and data.location",
        })
      end
    end
  end

  health.start("m_taskwarrior_d: dependencies")
  if pcall(require, "nui.popup") then
    health.ok("nui.nvim found")
  else
    health.warn("nui.nvim not found; TWView, TWEditTask and saved-query popups will fail", {
      "Install https://github.com/MunifTanjim/nui.nvim",
    })
  end

  health.start("m_taskwarrior_d: setup")
  local plugin = package.loaded["m_taskwarrior_d"]
  if plugin and plugin._config and plugin._config.checkbox_pattern then
    health.ok("setup() has been called")
    if plugin._config.display_due_or_scheduled then
      health.info("Due/scheduled virtual text is enabled")
    end
  else
    health.warn("setup() has not been called; no :TW* commands are registered", {
      "Call require('m_taskwarrior_d').setup({}) in your config",
    })
  end

  local save_file = vim.fn.stdpath("data") .. "/m_taskwarrior_d.json"
  if vim.fn.filereadable(save_file) ~= 1 then
    health.info("Saved-queries file not created yet: " .. save_file)
  else
    local fd = io.open(save_file, "r")
    local content = fd and fd:read("*a") or ""
    if fd then
      fd:close()
    end
    if pcall(vim.json.decode, content) then
      health.ok("Saved-queries file is valid JSON: " .. save_file)
    else
      health.error("Saved-queries file is not valid JSON: " .. save_file, {
        "Fix or delete the file; it is recreated on the next setup()",
      })
    end
  end
end

return M
