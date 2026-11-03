-- health.lua: every branch of :checkhealth m_taskwarrior_d.
--
-- Run with: scripts/test.sh lua/tests/test_health.lua

local this_file = debug.getinfo(1, "S").source:sub(2)
package.path = this_file:match("(.*/)tests/[^/]+$") .. "?.lua;" .. package.path
local H = require("tests.helpers")
local check, eq = H.check, H.eq

local tmp_dir = H.isolate_taskwarrior()
local health = require("m_taskwarrior_d.health")

-- Run the health check and return its report as "level: message" lines.
local function report()
  local lines = {}
  local function recorder(level)
    return function(msg)
      table.insert(lines, level .. ": " .. msg)
    end
  end
  local real = {}
  for _, level in ipairs({ "start", "ok", "warn", "error", "info" }) do
    real[level] = vim.health[level]
    vim.health[level] = recorder(level)
  end
  local ok, err = pcall(health.check)
  for level, fn in pairs(real) do
    vim.health[level] = fn
  end
  assert(ok, err)
  return lines
end

local function has_line(lines, pattern)
  for _, l in ipairs(lines) do
    if l:find(pattern) then
      return true
    end
  end
  error("no line matching " .. pattern .. " in:\n" .. table.concat(lines, "\n"), 2)
end

-- Answer `task --version` and `task ... count` with canned results.
local function fake_task(version, count)
  return function(cmd)
    return {
      wait = function()
        if cmd[2] == "--version" then
          if version == "throw" then
            error("spawn failed")
          end
          return version
        end
        return count
      end,
    }
  end
end

local ok_count = { code = 0, stdout = "3\n" }

H.section("before setup")

check("reports setup not called and no saved-queries file yet", function()
  local lines = report()
  has_line(lines, "^start: m_taskwarrior_d: Neovim")
  has_line(lines, "^ok: Neovim %d+%.%d+%.%d+")
  has_line(lines, "^warn: setup%(%) has not been called")
  has_line(lines, "^info: Saved%-queries file not created yet")
end)

check("reports nui.nvim missing", function()
  has_line(report(), "^warn: nui.nvim not found")
end)

H.section("after setup")

require("m_taskwarrior_d").setup({})
package.loaded["nui.popup"] = {}

check("reports setup, due text, nui and a valid saved-queries file", function()
  local lines = report()
  has_line(lines, "^ok: setup%(%) has been called")
  has_line(lines, "^info: Due/scheduled virtual text is enabled")
  has_line(lines, "^ok: nui.nvim found")
  has_line(lines, "^ok: Saved%-queries file is valid JSON")
  has_line(lines, "^ok: Task database readable")
end)

check("reports an invalid saved-queries file", function()
  vim.fn.writefile({ "{not json" }, tmp_dir .. "/m_taskwarrior_d.json")
  has_line(report(), "^error: Saved%-queries file is not valid JSON")
end)

H.section("Neovim and Taskwarrior versions")

check("reports a Neovim older than 0.10", function()
  H.with_stub(vim.fn, "has", function()
    return 0
  end, function()
    has_line(report(), "^error: Neovim 0.10%+ is required")
  end)
end)

check("reports a missing task binary", function()
  H.with_stub(vim.fn, "executable", function()
    return 0
  end, function()
    has_line(report(), "^error: `task` not found on %$PATH")
  end)
end)

check("accepts Taskwarrior 2.x and warns about 3.x", function()
  H.with_stub(vim, "system", fake_task({ code = 0, stdout = "2.6.2\n" }, ok_count), function()
    has_line(report(), "^ok: Taskwarrior 2.6.2$")
  end)
  H.with_stub(vim, "system", fake_task({ code = 0, stdout = "3.5.0\n" }, ok_count), function()
    has_line(report(), "^warn: Taskwarrior 3.5.0 found")
  end)
end)

check("warns about an unparseable version", function()
  H.with_stub(vim, "system", fake_task({ code = 0, stdout = "devel\n" }, ok_count), function()
    has_line(report(), "^warn: Could not parse Taskwarrior version")
  end)
end)

check("reports a failing or unstartable `task --version`", function()
  H.with_stub(vim, "system", fake_task({ code = 1, stdout = "", stderr = "bad rc\n" }, ok_count), function()
    has_line(report(), "^error: `task %-%-version` failed: bad rc$")
  end)
  H.with_stub(vim, "system", fake_task("throw", ok_count), function()
    has_line(report(), "^error: `task %-%-version` failed: .*spawn failed")
  end)
end)

check("reports an unreadable task database", function()
  local bad_count = { code = 2, stdout = "", stderr = "no data\n" }
  H.with_stub(vim, "system", fake_task({ code = 0, stdout = "2.6.2\n" }, bad_count), function()
    has_line(report(), "^error: `task count` failed: no data$")
  end)
end)

H.finish()
