# 0003 Paragraph, real

Status: done

Goal: a Markdown document's paragraphs are parsed by the real block
parser and hard-wrapped to the preview width (wide chars counted by
display width), with the source map and scroll sync still correct.

Brings: `core/text` (display width, wrap, pad), `markdown/block`
(paragraphs only, replacing the stub), a `width` in the render `ctx`,
wrapping in `document/render`, and the golden runner with the first
golden fixtures.

Touches: `lua/doc_preview/{core/text,markdown/block,document/render,config,session}.lua`,
`tests/unit/`, `tests/golden/`, `tests/integration/`, `Makefile`,
`doc/testing.md`.

Tests:

* unit: `core/text` (ASCII, CJK/emoji wide chars, long words, empty
  input, no result line wider than `width`); `markdown/block` (source
  ranges, paragraph/blank-line rules, lazy continuation lines, leading
  indent up to 3 spaces, trailing spaces stripped); renderer on hand-built
  trees with a given `ctx.width`.
* golden: `tests/golden/markdown/<name>.in|.out` at a fixed width.
* integration: `scroll_sync_spec.lua` and `scroll_flicker_spec.lua` keep
  passing.

Wrapping and the source map: the stub produced one paragraph per chunk
with the map `out_start..out_end` -> `src_start..src_end` where the
output line count equalled the source chunk length by construction of the
fixtures. Wrapping breaks that: a paragraph can now occupy more or fewer
output lines than source lines. `Out:src_to_out` / `Out:out_to_src`
already interpolate with the offset clamped to the entry; keep the one-map-entry-per-block
granularity (`doc/architecture.md` 4.1) and do not add per-line entries.
The earlier scroll-sync fix assumed one paragraph per chunk with a
simple mapping, so every task that touches the renderer or the map must
keep `tests/integration/scroll_sync_spec.lua` and
`tests/integration/scroll_flicker_spec.lua` passing (their fixtures use
short one-line paragraphs, so wrapping must be a no-op for them). If a
spec needs a change, say why in the task notes.

## Tasks

- [x] 1. `core/text.lua` + `tests/unit/text_spec.lua`: `width(s)`
   (`vim.fn.strdisplaywidth`, plain string, tabs not special-cased by
   callers), `wrap(s, width)` returning `string[]` (greedy word wrap on
   spaces, words longer than `width` hard-split at character boundaries
   without ever splitting a wide char, so a wide char that does not fit
   moves to the next line; `width < 1` treated as 1; collapses runs of
   whitespace and newlines to a single space), and `pad(s, width,
   align?)`. Pure functions, no state, no dependency on other plugin
   modules.
- [x] 2. `markdown/block.lua` real paragraphs + `tests/unit/markdown_block_spec.lua`:
   replace the stub with a line-based block pass that emits `paragraph`
   nodes with `src_start`/`src_end` (blank-line separated; a paragraph's
   inline text is the joined lines, each stripped of up to 3 leading
   spaces and trailing whitespace; soft breaks kept as `\n` in the
   `text` value for now). Pure `string[] -> document.model`, no Neovim
   API. Anything not a paragraph still falls back to a paragraph (other
   block kinds arrive in later slices); `model.validate` must accept the
   result. The empty document keeps the `document(blocks, 1, max(#lines,1))`
   shape. Port nothing: record in a comment that CommonMark section "Paragraphs"
   is the reference (no code copied, so no `doc/references.md` entry yet).
- [x] 3. Width in the render `ctx`: `config.lua` gains `max_width = 100`
   (`doc/architecture.md` section 8); `session.lua` computes `width =
   min(preview window width, max_width)` at render time (fallback
   `max_width` when there is no window) and passes `ctx = { width =
   width }` to `render.render`. No resize handling (later slice). Unit
   check for the width computation if it is a separate function; adjust
   `session_spec` only if it asserts `ctx`.
- [x] 4. `document/render.lua` paragraph wrapping + renderer unit tests in
   `tests/unit/document_spec.lua`: the paragraph handler wraps the
   joined inline text with `core/text.wrap(text, ctx.width)` (default
   width when `ctx.width` is nil), one `add_map` entry per paragraph
   spanning all wrapped lines -> `src_start..src_end`. Tests: a long
   paragraph produces several lines, none wider than `ctx.width`; wide
   chars; map entry covers exactly the wrapped lines; a 1-line source
   paragraph that wraps to 3 output lines maps both directions via
   `src_to_out`/`out_to_src` (add cases to `tests/unit/out_spec.lua` for
   many-to-few and few-to-many entries if missing). Then run
   `tests/integration/scroll_sync_spec.lua` and `scroll_flicker_spec.lua`
   unchanged; both must pass.
- [x] 5. Golden runner + first fixtures: `tests/golden_spec.lua`-style
   runner at `tests/golden/golden_spec.lua` (run by a new `make
   test-golden`, included in `make test`; add it to `.PHONY` and `help`)
   that, for each `tests/golden/<fmt>/<name>.in`, parses with the
   frontend for `<fmt>` (only `markdown` now), renders at a fixed
   width (default 40, optional first line directive is not needed: use a
   `<name>.width` file if present), and compares the lines to
   `<name>.out`. On mismatch print a readable line diff (expected vs
   actual); `UPDATE_GOLDEN=1` rewrites the `.out` files instead of
   failing. Fixtures (hand-reviewed, committed with their `.out`):
   `paragraph-wrap` (ASCII long text), `paragraph-wide` (CJK and emoji at
   the wrap boundary), `paragraph-multi` (several paragraphs, extra blank
   lines collapsed), `paragraph-longword` (hard split). Document the
   runner, directory layout and `UPDATE_GOLDEN` in `doc/testing.md` 1 and
   `README.md`. The golden layer only asserts lines (no `.spans`
   yet, nothing produces spans).
- [x] 6. Integration spec `tests/integration/paragraph_wrap_spec.lua`: open
   a preview of a buffer containing a long paragraph and a CJK paragraph,
   wait for the render, assert preview lines are wrapped to the window
   width (no line's display width exceeds it), and that moving the source
   cursor into the middle of the long paragraph puts the preview cursor
   inside the wrapped range (not off the end). Then `agent-test --full`
   passes, including both scroll specs.

## Done when

`:DocPreview open` on a Markdown file shows paragraphs hard-wrapped to
`min(window width, max_width)` with wide chars never split or overflowing;
scroll/cursor sync still works across wrapped paragraphs; unit, golden and
integration specs (including `scroll_sync_spec.lua` and
`scroll_flicker_spec.lua`) pass; `UPDATE_GOLDEN=1 make test-golden`
regenerates the fixtures and the diff is empty.

## Out of scope

Headings and every other block kind, inline parsing (emphasis, code spans,
links), highlight spans and `.spans` goldens, the CommonMark/pair runner
and `tests/pairs/`, resize re-render, per-line map refinement, hanging
indents (lists, quotes), RST.

## Notes

- `core/text.width` uses `nvim_strwidth`, not `strdisplaywidth`: the latter
  depends on the current window and over-counts a wide char at the last column.
- `Out` translate now interpolates linearly inside an entry (ceil on the
  src->out side), as `doc/architecture.md` 4.1 says. Needed because
  `scroll_flicker_spec.lua` runs on `doc/architecture.md` (tables, code, long
  lines), so wrapping is not a no-op there; offset-preserving clamping scrolled
  the preview. Both scroll specs are unchanged and pass.
- `tests/integration/session_spec.lua` line 79 changed: soft breaks are now
  collapsed by wrapping (`hello` / `world` -> `hello world`).
