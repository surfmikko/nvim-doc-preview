# 0020 Layouts

Status: done

Goal: `layout = vsplit | hsplit | replace` works, including
`:DocPreview open [layout]`, with `replace` flipping the preview in and out
of the source window.

Touches: `session.lua` (window ownership, `winsaveview` save/restore,
`bufhidden=wipe` on the preview in `replace`, window-local options
restored on flip back), `sync.lua` (`sync` no-op in `replace`,
`<CR>` flip-and-jump), `plugin/doc_preview.lua` (`open <layout>` argument
and completion, error on invalid name), `config.lua` (only if 0018 left
`hsplit`/`replace` as "not yet supported"), `tests/integration/layout_spec.lua`
(new).

Brings: `doc/architecture.md` 5.1.1 in full. This had no slice in the
explorer map (only `hsplit` and the command argument were assigned to the
config issue); added as its own issue because `replace` (flip, view
save/restore, wipe-on-close, user-owned window) is a sizeable feature.
Width in every layout stays `min(window width, max_width)`.

Tests: integration: `hsplit` opens below; `replace` shows the preview in the
same window, content sync continues while the source is hidden, flip back
restores the saved view if the preview cursor was not moved and otherwise
maps the cursor, `<CR>` flips back and jumps, closing the window or showing
another buffer wipes the preview and tears down without restoring the view,
unsaved source changes survive, no leaked autocmds/extmarks, invalid layout
argument opens nothing.

References: `doc/architecture.md` 5.1, 5.1.1, 5.2, 5.4, 8;
`doc/testing.md` 1.1.

Depends on: 0018 (`layout` key and validation), 0008 (`<CR>`, `q`,
`sync on|off`), 0017 (resize in shared window, optional).

Out of scope: layouts beyond the three names, per-filetype layout.

## Current state (checked at planning time)

- `hsplit` already works (`SPLITS` in `session.lua`; `layout_spec.lua` has an
  hsplit test). `config.lua` already validates all three names; no change.
- `session.open` rejects `replace` with a "not yet supported (issue 0020)"
  notification (`layout_spec.lua` asserts it; that test is replaced by task 2).
- `init.lua` `open`/`toggle` take no layout argument (`M[name](words[2])`
  passes the word only to `sync`); `complete` knows only `sync on|off`.
- Sessions do not record their layout; `sync.attach` always wires cursor and
  scroll autocmds on `src_win`/`prev_win` and a `WinClosed` on `prev_win`.
- Size gate is 400 lines per file in `lua/` (`session.lua` 207, `sync.lua`
  267): put the replace code in a new module under `lua/doc_preview/` (for
  example `replace.lua`, same level as `sync.lua`, no new layer) rather than
  growing those files.

## Tasks

- [x] 1. Layout argument and session layout: `session.open(src_buf, layout)`
  stores `s.layout` (argument, else `config.options.layout`); `init.lua`
  `open`/`toggle` accept `[vsplit|hsplit|replace]`, invalid name reports
  `DocPreview: ...` error naming the allowed values and opens nothing;
  `complete` offers the three names after `open`/`toggle`; `open` with an
  existing session of the same layout is a no-op, of another layout closes it
  and reopens in the requested one (architecture 5.2); `toggle` with a session
  closes it. `replace` still guarded as unsupported. Tests in
  `layout_spec.lua`: `open hsplit` overrides a `vsplit` config for that
  session only, same-layout reopen keeps the session, layout switch
  vsplit -> hsplit reopens, invalid argument opens nothing, completion.
- [x] 2. `replace` open and flip back (basic): new `replace.lua` plus a layout
  branch in `session.open`/`session.close`. Open: `s.prev_win = s.src_win`,
  save `winsaveview()` in `s.src_view`, `nvim_win_set_buf` the preview buffer
  in the current window (source buffer stays loaded and unmodified), render as
  usual (width from the shared window); no extra window. `close`/`toggle`/
  preview `q`: tear down the session and `nvim_win_set_buf` the source back,
  `winrestview(s.src_view)`, never close the window. Remove the unsupported
  guard and replace its test; update `doc/architecture.md` 8 implementation
  note (drop "reported as not yet supported until 0020"). Tests: preview
  shown in the same window and window count unchanged, content sync continues
  while the source is hidden (edit the source via `nvim_buf_set_lines` from
  another window or `nvim_buf_call`), flip back restores the exact saved view,
  unsaved source changes survive a round trip, `toggle` flips both ways.
- [x] 3. `replace` cursor mapping, `<CR>` and window options: on open, place
  the preview cursor/topline at `src_to_out(source cursor line)` keeping the
  same relative screen row (once, after the first render lands since
  `s.output` is needed); on flip back, if the preview cursor was not moved
  since open, restore the saved view exactly, otherwise set the source cursor
  to `out_to_src(preview cursor)` with the same relative screen row;
  `sync.jump_to_source` in `replace` flips back and jumps instead of
  switching windows (works regardless of `sync` flags); record window-local
  options the plugin sets on the shared window and restore them on flip back.
  Tests: open maps the cursor, unmoved cursor restores the exact view, moved
  cursor lands on the mapped source line, `<CR>` flips back and jumps, a
  window option set by the plugin (e.g. `wrap`/`cursorline`, whatever the
  preview sets) is restored.
- [x] 4. `replace` teardown, sync no-op and leak checks: in `replace`
  `sync.attach` registers no cursor/scroll autocmds and no `WinClosed` on a
  plugin-owned window; instead it watches the user's window: closing it, or
  showing another buffer in it (`BufWinLeave`/`BufWipeout` of the preview
  buffer through `bufhidden=wipe`), tears the session down without restoring
  the view (source buffer stays loaded, unsaved changes kept); `WinResized`/
  `VimResized` re-render for the shared window with no re-sync step;
  `DocPreview sync on|off` is a no-op in `replace` (no error). Tests: closing
  the window wipes the preview and removes the session, `:edit other` in the
  window does the same without view restore, `sync off`/`on` do nothing and
  do not throw, resize of the shared window re-renders when the effective
  width changes, after any teardown the augroup, timer and extmarks are gone
  (no leaks, same checks as `session_spec.lua`). Close the issue after host
  verification of the UI-dependent `WinResized` case if it needs an attached
  UI (see `resize_spec.lua`); mark `(host verify: ...)` only if it cannot run
  in the sandbox.
