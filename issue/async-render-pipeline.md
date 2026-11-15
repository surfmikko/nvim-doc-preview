# 0002 Async render pipeline

Status: done

Goal: `:DocPreview open|close|toggle` mirrors the source buffer into a
read-only split through the full async path, before any real parser
exists.

Brings: `Session`, the coroutine job runner with time slicing and
`yield_point()`, generation counter and cancel, `core/out` (lines,
spans, source-map entries), `document/model` (`document`, `paragraph`,
`text` only), `document/render`, a stub frontend (blank-line-separated
chunks become paragraphs, no inline parsing), debounced refresh, and the
`User DocPreviewRendered` / `wait()` test hooks.

Touches: `lua/doc_preview/{core/out,core/job,document/model,document/render,markdown/block,config,sync,session,init}.lua`,
`plugin/doc_preview.lua`, `tests/unit/`, `tests/integration/`.

Tests:

* unit: runner, cancel, `core/out`.
* integration (in-process, `vim.wait` + the rendered hook): open/close,
  slow block does not block input, second edit cancels the first, stale
  result never lands, no leaked timers/autocmds.
* slow blocks are simulated by a test-only hook in the renderer, not by
  real content.

## Tasks

- [x] 1. `core/out.lua`: builder (`add_line`, `add_span`, `add_map`,
   `append` with rebasing). Unit spec `tests/unit/out_spec.lua`.
- [x] 2. `core/job.lua`: coroutine runner (`run(fn, opts)`, one 0 ms timer
   per slice, `cancel()`, `yield_point()` no-op outside a job). Unit spec
   `tests/unit/job_spec.lua` (async, slicing, cancel, error, timer closed).
- [x] 3. `document/model.lua` (`document`, `paragraph`, `text`, kind
   registry, `validate`), `document/render.lua` (paragraph handler,
   placeholder for unknown kinds, `test_hook`), stub frontend
   `markdown/block.lua` (blank-line chunks to paragraphs). Unit spec
   `tests/unit/document_spec.lua`.
- [x] 4. `config.lua` (`debounce_ms`, `slice_ms`, `split`), `sync.lua`
   (autocmds, debounce timer, teardown), `session.lua` (preview
   buffer/window, generation counter, render job, apply, `wait`, the
   `User DocPreviewRendered` event), `init.lua` and `plugin/doc_preview.lua`
   (`:DocPreview open|close|toggle`).
- [x] 5. Integration spec `tests/integration/session_spec.lua`: open/close/
   toggle, close via window and via source buffer, debounced refresh,
   slow block does not starve the loop, second edit cancels the first,
   stale result never lands, no leaked timer/augroup/job.
- [x] 6. `agent-test --full` passes.

## Done when

`:DocPreview open` mirrors the source buffer into a read-only split
through the async path; edits re-render after the debounce; all unit and
integration specs pass.

## Out of scope

Real Markdown parsing, wrapping of wide chars, highlights,
cursor sync, child-Neovim RPC helper, `refresh`/`sync` subcommands, resize, block cache.
