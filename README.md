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

- Dectect task (checkbox) in Markdown or similar files and register the task into TaskWarrior.
  - Only in Markdown with ( - [ ]) at the moment
- Bidirectionally manage the task.
- Best effort to add contexts to the tasks:
  - Tags
  - Dependencies
  - Project
  - Status

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

Thank you for using the Neovim Lua Plugin! If you find it helpful, please consider
 starring the repository.
