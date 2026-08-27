# Product Context: m_taskwarrior_d.nvim

## Why This Exists
Taskwarrior is a powerful CLI task manager, but working with it alongside Markdown notes requires constant context switching. Existing solutions like taskwiki depend on Vimwiki, which conflicts with popular Markdown plugins (obsidian.nvim, mkdnflow.nvim, markdown.nvim). This plugin fills the gap by managing Taskwarrior tasks inside regular Markdown files.

## User Experience Goals
- Markdown-first: tasks live in `.md` files as normal checkboxes
- Unobtrusive: Taskwarrior IDs are concealed; inline attributes are parsed and hidden
- Fast: opening/saving Markdown files should not freeze Neovim, even with many tasks
- Familiar: commands mirror Taskwarrior concepts (sync, query, toggle, run)

## Key Features
- Detect `- [ ]` / `- [x]` style checkboxes and register them in Taskwarrior
- Inline Taskwarrior attribute parsing (`project:X`, `+tag`, `due:friday`, etc.)
- Virtual text rendering for due/scheduled dates (`TWShowDueOrScheduled`)
- Query view to render Taskwarrior reports inside Markdown (`TWQueryTasks`, `TWBufQueryTasks`)
- Dependency tracking via nested checkboxes
- Edit/view tasks via floating windows using `nui.nvim`

## Pain Point
Performance degrades as the number of tasks in a buffer grows. The plugin currently spawns one `task` process per UUID for sync, due-date rendering, and query operations, causing noticeable lag on buffer enter/save.
