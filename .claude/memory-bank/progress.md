# Progress: m_taskwarrior_d.nvim

## What Works
- Commands/autocmds, checkbox detection, bidirectional sync
- Batched Taskwarrior access: `task.get_tasks_bulk` (async, 100-UUID chunks), `get_tasks_bulk_sync`, batched `task mod` (50-UUID chunks, `rc.bulk=0`) in `apply_context_data`
- `sync_tasks`: one batched export into a `task_cache`, then each line synced once
- Due/scheduled virtual text: async, generation-claimed so overlapping renders don't stack, re-reads lines after the export, correct UTC handling
- Conceal of `$id{}`/`$query{}` via a decoration provider (ephemeral extmarks per redraw)
- `:checkhealth m_taskwarrior_d`
- Query views, dependency rendering, nui.nvim popups

## Tests
- 8 suites, 157 checks, 100% line coverage (branch `chore/v0.11-tests-and-fixes`, 2026-11-03): test_dependencies, test_utils, test_task, test_commands, test_health, test_comment_markers, plus the original test_task_batch and test_sync_render. All pass on Taskwarrior 3.5.0 locally.

## Known Issues
- `get_tasks_bulk` runs export chunks in parallel (see activeContext open questions).
- `task add` and status modifications are still one process per task.
- `dep:` adds to a task's dependencies, so syncs never remove a dependency (deleted child lines, or grandchild deps written before the direct-children fix, stay).

## Next Steps
- Decide on sequential chunks / `rc.gc=off` for TW 2.x.
- Incremental `sync_tasks`.
