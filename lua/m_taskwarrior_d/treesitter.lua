-- Load Tree-sitter
local ts = require 'nvim-treesitter'
local parsers = require 'nvim-treesitter.parsers'

-- Set up the parsers you want to use (including Markdown)
parsers.get_parser_configs().markdown = {
  install_info = {
    url = 'https://github.com/tree-sitter/tree-sitter-markdown',
    files = { 'src/parser.c', 'src/scanner.cc' },
  },
}
local M = {}
-- Define the function to extract tasks
local function extract_tasks()
  local bufnr = vim.api.nvim_get_current_buf()
  local parser = parsers.get_parser(bufnr, "markdown")

  -- Parse the buffer
  parser:parse()


  -- Iterate over the tree to find task items
  local tasks = {}
  local tree = parser:parse()[1]

  -- Define function to recursively traverse the tree
  local function traverse(node, tasks)
    if node:type() == "task_item" then
      local checked = node:named_child(0):named_child(0):has_error() and " " or "X"
      local task_text = node:named_child(1):raw()
      table.insert(tasks, { checked = checked, text = task_text })
    end

    for _, child in ipairs(node:children()) do
      traverse(child, tasks)
    end
  end
  traverse(tree:root(), tasks)
  return tasks
end

-- Expose the function
M.extract_tasks = extract_tasks
return M
