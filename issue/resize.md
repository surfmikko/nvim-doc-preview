# 0017 Resize

Status: done

Goal: resizing the preview window or the editor re-renders at the new width
and re-syncs the cursor.

Touches: `sync.lua` (`WinResized`, `VimResized` autocmds), `session.lua`
(detect `width` change, re-render through `invalidate`, re-sync),
`tests/integration/resize_spec.lua` (new).

Brings: `doc/architecture.md` 5.3.1 behaviour; cache invalidation on width
change (4.4).

Tests: integration: width change re-renders; no line exceeds the new
width, including tables, code and quotes (write those assertions when
0010-0014 have merged, or as a follow-up task here); scroll specs pass.

References: `doc/architecture.md` 4.4, 5.3.1, 9; `doc/testing.md` 1.1
(resize), 5 (robustness).

Depends on: 0004 (highlight re-applied after re-render); acceptance needs
0012 and 0014. Not parallel with 0008 or 0019 (shared `sync.lua`,
`session.lua`).

Out of scope: `replace` layout resizing (0020).

Note: there is no block cache yet (render is whole-document), so "cache
invalidation on width change" is satisfied by `invalidate` plus a full
`render`; nothing to flush. Existing specs that set `vim.o.columns` before
opening (`table_spec`, `images_spec`, `footnotes_spec`, `scroll_flicker_spec`)
keep working unchanged; resize specs are new.

## Tasks

- [x] 1. `session.lua`: record the width used by each render (`s.width = ctx.width` in `M.render`, capture it before the job starts). Add `M.resized(s)`: if `M.width(s) == s.width` return (height-only and max_width-capped resizes cost nothing); else `M.invalidate(s)` and `M.render(s)` directly (no debounce: resize events are already coalesced by Neovim). In `apply`, accept a `force_sync` flag (set by a resize render via `s.resync = true`, cleared in `apply`) so the cursor is re-synced via `sync.to_preview` (after clearing `s.guard`/`s.base`) even when the current window is the preview. Keep `open`'s handler table gaining `resized = M.resized`. Unit-ish check inside the new spec (task 3).
- [x] 2. `sync.lua`: in `attach`, add `WinResized` (callback returns unless `vim.v.event.windows` contains `s.prev_win`; ignore a closed session) and `VimResized` autocmds in the session augroup, both calling `s.handlers.resized(s)`; reuse the existing `on` helper or a small local helper so `attach` stays under cyclomatic complexity 10 and the file stays under 400 lines (now 207; split the autocmd registration into a local function if `attach` grows). `M.detach` already deletes the augroup, so nothing leaks; add a no-leak assertion to the spec. Window width changes also alter `s.base` row anchoring: clear `s.guard`/`s.base` in the resize path (task 1) before re-sync.
- [x] 3. `tests/integration/resize_spec.lua` (new): open a preview, change `vim.o.columns` / `nvim_win_set_width(prev_win, n)` after the first render, `doc_preview.wait`, assert the preview re-rendered (`DocPreviewRendered` fired, lines rewrapped, `s.width` updated) and no line exceeds the new width (`text.width`) for a long paragraph, a heading, a table, a fenced code block and a block quote (0010-0014 are merged; 0012 and 0014 acceptance included); narrowing then widening round-trips; a resize that leaves the width unchanged (height only, or beyond `max_width`) does not re-render; a resize while a job is running cancels it (generation bumped, stale result not applied); cursor stays mapped after re-render (source cursor line maps to the preview cursor row, also when the focus is in the preview); no autocmds left after close (`nvim_get_autocmds{group=...}` empty). Triggering: call `vim.api.nvim_exec_autocmds("VimResized"/"WinResized")` where a real resize is not delivered headless, in addition to a real `nvim_win_set_width`. `scroll_sync_spec` and `cr_jump_spec` must still pass.
- [x] 4. `doc/architecture.md` 5.3.1 / `doc/testing.md` 1.1: only adjust wording if behaviour differs (width-unchanged resize is a no-op; re-sync happens even with the preview focused); `README.md` one line noting the preview follows resizes. Mark Status done when verified.
- [x] 5. `agent-test --full` passes in the sandbox (all integration specs incl. existing table/images/footnotes/scroll ones, size and banned-API gates).
- [x] 6. (host verify) `make ci`: `stylua --check` and `luacheck` (cyclomatic complexity <= 10 per function) are not installable in the sandbox; run on the host and fix findings. (verified on host 2026-11-15)
