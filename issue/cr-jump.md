# 0008 `<CR>` jump

Status: done

Goal: `<CR>` in the preview moves the source cursor to the mapped line and
focuses the source window; `q` closes the preview; `:DocPreview sync on|off`
toggles cursor/scroll sync.

Touches: `sync.lua` (`jump_to_source`, reusing `out_to_src` and the
existing move helper; sync enabled flag); `session.lua` (buffer-local
maps set in `open`, removed by teardown); `plugin/doc_preview.lua`
(`sync` subcommand and completion); `README.md`/docs for the key;
`tests/integration/cr_jump_spec.lua` (new).

Brings: the only unfinished item of the scroll-sync roadmap line
(`issue/scroll-sync.md` out of scope) plus `q` and `sync on|off`, which
are in `doc/architecture.md` 5.2/8 but in no earlier roadmap line.
Default keys hard-coded until 0018 makes them configurable. The `sync`
no-op under `replace` is handled by 0020.

Tests: integration: `<CR>` jumps to the mapped line and focuses source,
works inside a wrapped paragraph and on a heading, no leaked keymap after
close, `q` closes, `sync off` stops cursor/scroll mirroring and `sync on`
resumes; scroll specs keep passing.

References: `doc/architecture.md` 5.2, 5.4 (last bullet), 8
(`keymaps.jump_to_source`, `close`); `doc/testing.md` 1.1.

Depends on: 0004 (must follow its `session.lua` span change). No
dependency on the parser slices, so it may run in a separate worktree
beside 0009-0016 (not beside 0017 or 0019: all edit `sync.lua` and
`session.lua`). Does not touch the Makefile.

Out of scope: configurable keys (0018), `replace` behaviour (0020).

## Tasks

- [x] 1. `sync.lua`: add `s.sync_enabled` (default true, set in `attach`) and make `follow` (both directions, `CursorMoved` and `WinScrolled` paths) return early when it is false; add `M.set_enabled(s, bool)` that, on enable, clears `s.guard`/`s.base` and calls `M.to_preview(s)` to resync. Cover with a case in the new `tests/integration/cr_jump_spec.lua` (call `set_enabled` directly: off stops mirroring both ways, on resumes).
- [x] 2. `sync.lua`: add `M.jump_to_source(s)`: map the preview cursor line via `s.output.out_to_src` (no-op if no output or no mapping), move the source cursor with the existing `move` helper (so the guard records it and no echo sync fires), then `nvim_set_current_win(s.src_win)`. Works regardless of the sync flag. Tests in `cr_jump_spec.lua`: jump on a heading and inside a wrapped paragraph (long line wrapped to several preview lines) lands on the mapped source line and focuses the source window; no-op before the first render.
- [x] 3. `session.lua`: in `open`, set buffer-local normal-mode maps on `s.prev_buf` (`<CR>` -> `sync.jump_to_source(s)`, `q` -> `M.close(s)`; keys hard-coded, 0018 makes them configurable). Maps die with the buffer on teardown; confirm `close` leaves no leaked keymap on the source buffer or global maps (`nvim_get_keymap`/`nvim_buf_get_keymap` assertions). Tests: `<CR>` in the preview jumps and focuses source; `q` closes session, window and buffer; no leaked maps after close.
- [x] 4. `init.lua` and `plugin/doc_preview.lua`: allow a second argument (`nargs = "+"`; split `opts.args`), add `sync` to `M.subcommands`, implement `M.sync(arg)` accepting `on|off` (error notify otherwise, notify if no session) calling `sync.set_enabled`; completion returns `on`/`off` after `sync` and subcommands otherwise. Keep existing one-word commands working. Tests: `:DocPreview sync off` stops cursor/scroll mirroring, `sync on` resumes, bad argument notifies an error; `session_spec` and `scroll_sync_spec` still pass.
- [x] 5. `README.md` (and `doc/architecture.md` 5.2/5.4 only if wording needs adjusting): document `<CR>`, `q` and `:DocPreview sync on|off`; note keys are fixed until 0018 and `sync` under `replace` is handled by 0020.
- [x] 6. `agent-test --full` passes (stylua, luacheck and size gates per `doc/testing.md` 5 included); fix any regression in existing scroll/session specs.
  Host: run `make ci` (stylua --check and luacheck are not installable in the sandbox). Sandbox: `agent-test --full`, size and banned gates pass. (verified on host 2026-11-15)
