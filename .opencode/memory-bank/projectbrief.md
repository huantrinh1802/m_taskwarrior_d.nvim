# Project Brief: m_taskwarrior_d.nvim

## Overview
Neovim plugin that integrates Taskwarrior with Markdown documents. Allows users to manage Taskwarrior tasks directly from Markdown checkboxes without leaving Neovim.

## Core Goals
- Be a simple, non-obstructive tool for Markdown task management
- Bidirectionally sync Markdown checkboxes with Taskwarrior
- Avoid reinventing Taskwarrior's task management logic
- Support task context (projects, tags, dependencies) and query views

## Current Problem Statement
User reports that **all processes are slow**, especially rendering virtual text for due/scheduled dates. The primary cause is excessive synchronous calls to the `task` CLI (one process per task/UUID) during buffer operations like sync, query, and due-date rendering.

## Scope
- Optimize performance by batching Taskwarrior CLI calls
- Keep existing behavior and UI intact
- Minimal, maintainable changes to Lua modules
