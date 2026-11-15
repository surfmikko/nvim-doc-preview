# Nested-block render crash
Status:       done
Goal:         Deeply nested quotes and lists (100+ levels) render instead of throwing `loop in gettable`.
Touches:      `lua/doc_preview/document/render.lua` (ctx for blockquote at ~230, list_item at ~293), `tests/unit/` render spec
Source:       project review finding 1, report `.claude-data/var/report/reviewer-project-20261115-1201.md`
Parallel:     conflicts with no other review issue on source files (only `render.lua`; `robustness-tests` should run after it).

## Tasks

- [x] 1. `render.lua`: build the child ctx for `blockquote` and `list_item` by shallow copy (`vim.tbl_extend("force", ctx, {...})`) instead of `setmetatable({..}, {__index = ctx})`; shared registries (`links`, `footnotes`) stay shared. Unit tests: render documents with 200 nested quote levels and 200 nested list levels; assert no error, output lines within width, content present.

Done when: new unit tests pass and `agent-test` stays green.
Out of scope: a parser depth cap; the general fuzz spec (see `robustness-tests`).
