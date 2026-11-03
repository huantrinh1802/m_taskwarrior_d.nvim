std = "luajit"
-- vim, plus helpers defined as globals in utils.lua (also listed in .luarc.json)
globals = { "vim", "findIndex", "findPair" }
max_line_length = false

-- Ad-hoc scratch files, not part of the plugin
exclude_files = { "lua/test.lua" }

-- Pre-existing warnings (unused/overwritten locals). Remove a code from these
-- lists once its warnings are fixed.
files["lua/m_taskwarrior_d/init.lua"] = { ignore = { "211", "212", "311" } }
files["lua/m_taskwarrior_d/utils.lua"] = { ignore = { "111/_", "211", "311" } }
