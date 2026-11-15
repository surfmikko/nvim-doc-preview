# Scroll sync

Status: done

Goal: moving the cursor or scrolling in the source window keeps the
preview window aligned, and the other way round, using the source map
of the last applied render.

Touches: `lua/doc_preview/{core/out,sync,session}.lua`,
`tests/unit/out_spec.lua`, `tests/integration/scroll_sync_spec.lua`.

## Tasks

- [x] 1. `core/out.lua`: `Out:src_to_out(line)` and `Out:out_to_src(line)`
   (offset kept inside an entry, unmapped lines snap to the nearest
   entry, `nil` for an empty map). Unit tests in `tests/unit/out_spec.lua`.
- [x] 2. `sync.lua`: `CursorMoved`/`WinScrolled` autocmds for both windows
   in the session augroup, `to_preview`/`to_source` keeping the same
   window row; loop guard recording the position set programmatically
   (events arrive later from the event loop, so a flag is not enough).
   `session.lua`: record `src_win`, re-sync after each applied render
   (not while the preview is focused).
- [x] 3. Integration spec `tests/integration/scroll_sync_spec.lua`: both
   directions, no feedback loop, unmapped line snap, sync before the first
   render is a no-op, sync works while a re-render is running (uses the
   last applied output), nothing leaks on close.
- [x] 4. `agent-test --full` passes.

## Done when

Cursor and scroll in either window move the other to the mapped
position without oscillation; specs pass.

## Out of scope

`:DocPreview sync on|off`, `<CR>` jump from the preview, resize
re-sync, diagram-interior mapping, proportional mapping inside
wrapped blocks.
