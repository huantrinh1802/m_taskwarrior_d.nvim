# Mark TaskWarrior Down in Neovim

## Description

The plugin allow you to view, add, edit, and complete tasks without ever leaving the comfort of Neovim text
The goals of this plugin are:

- Be a simple tool without obstructing the view of the document
- Improve the workflow of task management in Markdown files
- Not reinvent the wheel of the way Taskwarrior manages tasks

## Installation

```lua
require("lazy").setup({
    {
        "huantrinh1802/m_taskwarrior_d.nvim",
        dependencies = { "MunifTanjim/nui.nvim" },
        config = function() {
            require("m_taskwarrior_d").setup()
        }
    }
})
```

### Features

- [x] Injected and concealed TaskWarrior task $id{5752e26d-b76e-4799-9f9f-016402ab0150}
- [ ] Dectect task (checkbox) in Markdown or similar files and register the task into TaskWarrior $id{cceb2bd6-83eb-42a0-9713-f5f7256d5cee}
  - [x] Work with Markdown with ( - [ ]) $id{f3d0233b-720b-41ee-9c91-9d046d3d6b0f}
  - [ ] Docstring in Python $id{b2f4cdd8-cca1-4191-a2c6-d68d608b81dd}
  - [ ] JSDoc in JavaScript $id{26b05754-afc0-4f44-9197-fb19d01698f8}
- [>] Bidirectionally manage the task $id{cc871e54-088b-49e7-b8a3-0cc22ae81e04}
- [>] Best effort to add contexts to the tasks: $id{03714337-dd43-4556-b359-42f91955b4d6}
  - [ ] Use treesitter for better capturing contexts $id{20b3fdbf-436c-4ea1-8e58-0fe8c63c714f}
  - [ ] Tags $id{2cc75c5d-7d2c-4805-aac7-bc367f60bc6f}
  - [>] Dependencies $id{205b321d-76f9-4ec1-8f97-679cfa850c59}
    - [x] Detect nested subtasks and update related tasks $id{7fba9ce7-11fc-472c-ab07-9c2e7a069a44}
  - [ ] Project $id{f35f9475-7732-414e-9d2b-e006da675366}
- [x] View individual task on hover $id{e050d326-f5b4-4608-8024-ffedaaa0eed5}
- [x] Edit task detail within Neovim (through toggleterm) $id{166d033c-c831-4e28-9ba7-554518537dc5}

## Maybe Feature

- Interface for displaying TaskWarrior reports
- Query tasks to other pages similar to viewport in `taskwiki` or `dateview` in Obsidian
- Better UI for advance taskwarrior usage such as overdue, waiting, and more

## Out of scope

- UI for editing task (I am reusing `task {id} edit`)

## Dependencies

- [TaksWarrior](https://taskwarrior.org/) (pre3.0) (hard required)
  - Have not tested v3.0 but it may have a breaking change due to its move to SQLite as the main storage engine
- [jq](https://jqlang.github.io/jq/) (required)
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim)
  - For all UIs in the plugin

## Work Well With

- [mkdnflow.nvim](https://github.com/jakewvincent/mkdnflow.nvim)
  - This plugin provides comprehensive utilities for Markdown files
  - Caveat: you need to disable/not use toggle checkbox from this plugin
- [obsidian.nvim](https://github.com/epwalsh/obsidian.nvim/tree/main)
  - If you use Obsidian for note taking, this plugin is highly recommended
  - This plugin provides some nice concealment and utilities for Obsidian

## Similar To

- [taskwiki](https://github.com/tools-life/taskwiki)
  - This plugin provides better utilities for managing tasks in Markdown files with TaskWarrior
  - Reasons I decided not to use this plugin:
    - Rely on [Vimwiki](https://github.com/vimwiki/vimwiki), which has wonky interactions with `obsidian.nvim` and `mkdnflow.nvim` (due to special filetype `vimwiki`)
    - Disclaimer: there may be a way to configure to make Vimwiki and markdown plugins to work together but I decided to write m_taskwarrior_d.nvim

## Installation

```lua
{
    "huantrinh1802/m_taskwarrior_d.nvim/",
    ft = "markdown",
    dependencies = { "MunifTanjim/nui.nvim" },
    config = function()
    -- Require
      require("m_taskwarrior_d").setup()
    -- Optional
      vim.api.nvim_set_keymap("n", "<leader>te", "<cmd>TWEditTask<cr>", { desc = "TaskWarrior Edit", noremap = true, silent = true })
      vim.api.nvim_set_keymap("n", "<leader>tv", "<cmd>TWView<cr>", { noremap = true, silent = true })
      vim.api.nvim_set_keymap("n", "<leader>tu", "<cmd>TWUpdateCurrent<cr>", { noremap = true, silent = true })
      vim.api.nvim_set_keymap("n", "<leader>ts", "<cmd>TWSyncTasks<cr>", { noremap = true, silent = true })
      vim.api.nvim_set_keymap(
        "n",
        "<c-space>",
        "<cmd>TWToggle<cr>",
        { silent = true }
      )
    -- Be caution: it may be slow to open large files, because it scan the whole buffer
      vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
        group = vim.api.nvim_create_augroup("TWTask", { clear = true }),
        pattern = "*.md,*.markdown", -- Pattern to match Markdown files
        callback = function()
          vim.cmd('TWSyncTasks')
        end,
      })
    end,
  },
```

## Usage

- Default configurations:

```lua
{
  -- The order of toggling task statuses
  task_statuses = { " ", ">", "x", "~" },
  -- The mapping between status and symbol in checkbox
  status_map = { [" "] = "pending", [">"] = "started", ["x"] = "completed", ["~"] = "deleted" },
  -- More configurations will be added in the future
}
```

### Statuses

- `pending`: corresponding to `pending` status
- `started`: corresponding to `pending` status and `stated` tag
- `completed`: corresponding to `completed` status
- `deleted`: corresponding to `deleted` status

If you are using `obsidian.nvim`, you can use the following configuration:

```lua
{
  ui = {
    checkboxes = {
      [" "] = { char = "󰄱", hl_group = "ObsidianTodo" },
      ["x"] = { char = "", hl_group = "ObsidianDone" },
      [">"] = { char = "", hl_group = "ObsidianRightArrow" },
      ["~"] = { char = "󰰱", hl_group = "ObsidianTilde" },
               },
    hl_groups = {
      ObsidianTodo = { bold = true, fg = "#f78c6c" },
      ObsidianDone = { bold = true, fg = "#89ddff" },
      ObsidianRightArrow = { bold = true, fg = "#f78c6c" },
      ObsidianTilde = { bold = true, fg = "#ff5370" },
      ObsidianBullet = { bold = true, fg = "#89ddff" },
      ObsidianRefText = { underline = true, fg = "#008080" },
      ObsidianExtLinkIcon = { fg = "#008080" },
      ObsidianTag = { italic = true, fg = "#89ddff" },
      ObsidianHighlightText = { bg = "#75662e" },
    },
  },
}
```

### Commands

- `TWToggle`: toggle status of task
- `TWSyncTasks`: traverse the current buffer and sync all tasks
- `TWUpdateCurrent`: quickly update the description of the task so you don't have to use the edit command
- `TWEditTask`: toggle a float window, which can edit the task. Using the `task {id} edit`
- `TWView`: a quick view of more details of the task

### Task Dependencies

- Nested checkboxes are depended on the parent checkbox
```markdown
- [ ] Task 1 # Has 1.1, 1.2, 1.2.1 as dependencies $id{d4452942-ac6e-46c6-b110-001ea731c676}
  - [ ] Task 1.1 # Has none $id{53389315-5975-4db9-a796-1cd2514e1be1}
  - [ ] Task 1.2 # Has 1.2.1 as dependency $id{ea843624-37c0-429c-89c6-19f661149668}
    - [ ] Task 1.2.1 $id{792e57a6-ea55-4c9e-ab32-9e840d66088d}
```
## License

This plugin is licensed under the MIT License. See the LICENSE file for more
 details.

## Issues

If you encounter any issues or have suggestions for improvements, please open
 an issue on the GitHub repository.

## Contributors

- Ben Trinh <huantrinh1802@gmail.com>

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/W7W4VVT9J)

Thank you for using the Neovim Lua Plugin! If you find it helpful, please consider
 starring the repository.
