# Project Brief: m_taskwarrior_d.nvim

## Overview
Neovim plugin that integrates Taskwarrior with Markdown documents. Allows users to manage Taskwarrior tasks directly from Markdown checkboxes without leaving Neovim.

## Core Goals
- Be a simple, non-obstructive tool for Markdown task management
- Bidirectionally sync Markdown checkboxes with Taskwarrior
- Avoid reinventing Taskwarrior's task management logic
- Support task context (projects, tags, dependencies) and query views

## Original Problem Statement
The user reported that **all processes were slow**, especially rendering virtual text for due/scheduled dates. The cause was one synchronous `task` process per task/UUID during sync, query and due-date rendering. The current branch addresses this by batching.

## Scope
- Optimize performance by batching Taskwarrior CLI calls
- Keep existing behavior and UI intact
- Minimal, maintainable changes to Lua modules
