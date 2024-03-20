# Mark TaskWarrior Down in Neovim

## Description

Allows users to easily interact with their TaskWarrior tasks directly within Neovim.
With this plugin, users can view, add, edit, and complete tasks without ever leaving their text editor.
Within text files, such as Markdown, this plugin provides a convenient way to manage tasks bidirectionally.

## Installation

```lua
require("lazy").setup({
    {
        "huantrinh1802/m_taskwarrior_d.nvim",
        dependencies = { "akinsho/toggleterm.nvim" },
        config = function() {
            require("m_taskwarrior_d").setup()
        }
    }
})
```

## Features

- [x] Injected and concealed TaskWarrior task
- [ ] Dectect task (checkbox) in Markdown or similar files and register the task into TaskWarrior
  - [x] Work with Markdown with ( - [ ])
  - [ ] Docstring in Python
  - [ ] JSDoc in JavaScript
- [ ] Bidirectionally manage the task
- [>] Best effort to add contexts to the tasks:
  - [ ] Use treesitter for better capturing contexts
  - [ ] Tags
  - [>] Dependencies
    - [x] Detect nested subtasks and update related tasks
  - [ ] Project
- [>] View individual task on hover
- [x] Edit task detail within Neovim (through toggleterm)

## Maybe Feature

- Interface for displaying TaskWarrior reports

## Demo

TBC

## Dependencies

- [TaksWarrior](https://taskwarrior.org/) (pre3.0) (hard required)
  - Have not tested v3.0 but it may have a breaking change due to its move to SQLite as the main storage engine
- [jq](https://jqlang.github.io/jq/) (required)
- [toggleterm](https://github.com/akinsho/toggleterm.nvim) (optional)

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

## Usage

TBC

## License

This plugin is licensed under the MIT License. See the LICENSE file for more
 details.

## Issues

If you encounter any issues or have suggestions for improvements, please open
 an issue on the GitHub repository.

## Contributors

- Ben Trinh <huantrinh1802@gmail.com>

Thank you for using the Neovim Lua Plugin! If you find it helpful, please consider starring the repository.
