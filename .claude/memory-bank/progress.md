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
- `lua/tests/test_task_batch.lua` (11 checks) and `lua/tests/test_sync_render.lua` (13 checks), run headless against a throwaway `TASKRC`/`TASKDATA`. Both pass on Taskwarrior 3.5.0.

## Known Issues
- `get_tasks_bulk` runs export chunks in parallel (see activeContext open questions).
- `task add` and status modifications are still one process per task.
- `check_dependencies` makes a parent depend on every deeper-indented line (grandchildren included); this predates the branch.

## Next Steps
- Decide on sequential chunks / `rc.gc=off` for TW 2.x.
- Incremental `sync_tasks`.
