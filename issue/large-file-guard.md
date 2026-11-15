# 0019 Large-file guard

Status: done

Goal: buffers over a line threshold warn once and switch to on-save
refresh instead of refresh on every edit.

Touches: `sync.lua` (`BufWritePost` instead of `TextChanged` over the
threshold), `session.lua` (warn-once flag), `config.lua` (threshold key,
default 5000), `tests/integration/large_file_spec.lua` (new).

Brings: `doc/architecture.md` 9 behaviour ("warn once and fall back to
on-save refresh").

Tests: integration: one warning only, no render on edit, render on save,
threshold configurable; scroll sync keeps working.

References: `doc/architecture.md` 5.3, 8, 9; `doc/testing.md` 1.1
(large-file guard).

Depends on: 0018 (threshold key; may hard-code first), 0017 (both touch
`sync.lua`; serialize).

Out of scope: incremental block cache (4.4), perf budget measurement.

## Tasks

Decisions fixed by this plan (the coder does not re-decide them):

- Config key `large_file_lines`, default `5000`, validated as a number >= 1 through the existing table-driven schema in `config.lua` (one `schema` entry plus one default; the validator itself is not touched). Read from `config.options` at event time, not cached at attach, so `setup()` changes apply to the next edit. "Large" means `nvim_buf_line_count(src_buf) > large_file_lines`, evaluated on every edit event, so a buffer that grows past (or shrinks below) the threshold switches mode without reopening.
- Guard policy lives in `sync.lua` (it owns the autocmds and the debounce); the warning (a `vim.notify` WARN, `doc_preview: <n> lines exceeds large_file_lines (<limit>); preview refreshes on save only`) lives in `session.lua`, passed to `sync.attach` as a new handler `large`. `s.warned` is set on first warning and never reset for that session (one warning per session, even if the buffer oscillates around the threshold).
- Over the threshold: `TextChanged`/`TextChangedI` do nothing (no `handlers.changed`, so a running render is not cancelled and no debounce is armed); `BufWritePost` on the source buffer calls the normal `M.changed` path (cancel, debounce, render). Under the threshold behaviour is unchanged. `BufWritePost` is registered always but is a no-op under the threshold (the edit events already rendered), so there is no double render.
- The initial render at `open` is unchanged (one async, cancellable render, not skipped); the warning is also emitted at `open` when the buffer is already large. Scroll/cursor sync is not touched: it works on the last applied `s.output` and the stale-output mapping is acceptable until the next save (clamped by `move`).
- `attach` in `sync.lua` is already long; register the edit autocmds in a new local `attach_edit(s, group)` (like `attach_resize`) so `attach` stays under cyclomatic complexity 10; keep `sync.lua` under 400 lines (241 now) and `session.lua` likewise (190 now).
- Out of scope: block cache, perf measurement, a per-buffer override command.

- [x] 1. `config.lua`: add `large_file_lines = 5000` to `M.defaults` and a `schema` entry (`is_number_min(1)`, allowed text `a number >= 1`). Extend `tests/unit/config_spec.lua`: default is 5000, a custom value is accepted, `0`, a string and `false` are rejected with the standard `large_file_lines must be a number >= 1, got ...` message, a rejected call leaves options untouched.
- [x] 2. `sync.lua`: add local `attach_edit(s, group)` registering `TextChanged`/`TextChangedI` (call `M.changed(s)` only when not `M.is_large(s)`; when large call `s.handlers.large(s)` so the warning fires on first crossing) and `BufWritePost` (call `M.changed(s)` only when `M.is_large(s)`), replacing the inline registration in `attach`. Add exported `M.is_large(s)` (line count vs `config.options.large_file_lines`, source buffer validity checked). Extend the `handlers` type annotation with `large: fun(s)`. Handlers are used by `session` in task 3 (give `large` a nil-safe call only if specs build handler tables by hand; check `tests/` for direct `sync.attach` callers).
- [x] 3. `session.lua`: add `M.warn_large(s)` (once per session via `s.warned`, `vim.notify` WARN with the message above) and pass `large = M.warn_large` in `open`'s handler table; in `open`, call `M.warn_large(s)` after attach when `sync.is_large(s)`. Keep `M.wait` correct: no pending debounce and no job under the threshold-edit path means `wait` returns immediately after an unsaved edit in a large buffer (document this in the spec comment).
- [x] 4. `tests/integration/large_file_spec.lua` (new; set `large_file_lines` small, e.g. 20, via `setup()` rather than generating 5000 lines, and reset options in `after_each`): (a) opening a buffer over the threshold warns exactly once (capture `vim.notify`) and still renders once; (b) edits over the threshold (several `TextChanged` via `nvim_buf_set_lines` plus `nvim_exec_autocmds`) produce no new warning, no `DocPreviewRendered`, preview lines unchanged; (c) `BufWritePost` (real `:write` to a temp file, or `nvim_exec_autocmds`) renders the new content; (d) under the threshold edits still render on change and never warn; (e) a buffer growing past the threshold warns once then switches to save-only, shrinking back resumes per-edit rendering without a second warning; (f) threshold is configurable (a larger `large_file_lines` keeps per-edit rendering for the same buffer; invalid value rejected by `setup`); (g) scroll/cursor sync still maps source to preview in a large buffer (reuse the `scroll_sync_spec` helpers); (h) a save while a debounced render is pending or a job is running cancels it (generation bumped, no stale apply); (i) no autocmds left after close (`nvim_get_autocmds{group=...}` empty).
- [x] 5. Docs: `doc/architecture.md` 8 (config listing and prose: add `large_file_lines`, default 5000) and 9 (replace "> 5000 lines, configurable" wording with the exact behaviour: edits ignored, save renders, one warning per session); `doc/testing.md` 1.1 only if its large-file wording differs; `README.md` config block gains `large_file_lines = 5000` plus one line on the behaviour. Set Status to "done except host check (task 7: `make ci`)" and update the 0019 row in `doc/plan.md` to match.
- [x] 6. `agent-test --full` passes in the sandbox (all integration specs, in particular `scroll_sync_spec`, `resize_spec`, `session_spec`, `command_spec`; size and banned-API gates).
- [x] 7. (host verify) `make ci`: `stylua --check` and `luacheck` (cyclomatic complexity <= 10 per function) are not installable in the sandbox; run on the host and fix findings. (verified on host 2026-11-15)

Task 7 host check: sandbox lacks stylua/luacheck; hand-checked `attach_edit`/`is_large`/`warn_large` (complexity < 10), files under 400 lines (sync 267, session 207, spec 200). Run `make ci` on the host.
