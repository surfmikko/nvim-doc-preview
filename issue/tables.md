# 0014 Tables

Status: done

Goal: GFM pipe tables render as box-drawn grids that fit `ctx.width`,
including wide characters, with an ascii fallback.

Touches: `markdown/block.lua` (table detection: header row plus delimiter
row), new `core/table.lua` (column fitting, cell wrap), new `core/box.lua`
(box glyphs, ascii fallback), `document/model.lua` (`table`: header, rows,
cells, align), `document/render.lua`, `core/highlight.lua` (header and
border groups), `tests/pairs/project_html.lua` (GFM table HTML).

Brings: pipe table parsing (escaped pipes, alignment, ragged rows),
column-width fitting with proportional shrink and cell wrapping, per-row
map entries (`doc/architecture.md` 4.1), `ctx.charset` use defaulting to
unicode until 0018.

Tests: unit for `core/table` (fitting, cell wrap, wide chars, minimum
widths) and `core/box`; own-input pairs for GFM "Tables (extension)"
(structure only; layout is checked by unit and layout invariants, not pair
output); golden; no line exceeds width; per-row map check.

References: GFM "Tables (extension)" (behaviour only); parse port from
`markdown-it` (MIT) `table.js`; the width-fitting algorithm is written
here (record "original" in `doc/references.md`; no permissive source cited
in the docs). `doc/architecture.md` 3, 4.1, 6.1, 7; `doc/document-model.md`
(`table`).

Depends on: 0006 (cell inlines), 0004. Tables inside list items are
optional (0011).

Out of scope: rst tables, colspan/rowspan.

## Decisions for the plan

- Model: `table{align, header, rows}` (`kind = "table"`, registered in
  `document/model.lua` `kinds`, `validate`: `align` entries nil/`left`/
  `center`/`right`, `header` and every row a list of cells, each cell
  `{inlines}`, every row exactly `#align` cells). Constructor
  `M.table(align, header, rows, src_start, src_end)`. Rows are single
  source lines, contiguous after container stripping: header is
  `src_start`, the delimiter row `src_start + 1`, body row `i` is
  `src_start + 1 + i`, so no per-row table is stored. colspan/rowspan stay
  absent (rst only, out of scope).
- Parse (`markdown/table.lua`, new; `block.lua` is at 246 lines, so it only
  gains a short call; `container.lua` 273 and `inline.lua` 366 are not
  touched beyond tiny hooks): a delimiter row (cells `:?-+:?`, optional
  outer pipes, at least one `|` or a single-column form with an outer pipe,
  indent 0-3) directly below a header row whose cell count equals the
  delimiter's cell count starts a table; the header is the last line of
  the open paragraph (earlier paragraph lines flush as their own
  paragraph) or a fresh line. Body rows run until a blank line or a line
  that starts another block (the existing `scan` checks run first for
  ATX, fence, quote, list, thematic, HTML); a row with fewer cells is padded
  with empty cells, extra cells are dropped. Cell splitting: `\|` is an
  escaped pipe (kept as `|` in the cell text), a pipe inside a code span
  still splits unless escaped (GFM). Cell text is trimmed and parsed with
  `inline.parse(text, refs)` in `build`. `collect_definitions` and
  `take_task_box` skip `table` entries like `html`.
- Layout (`core/table.lua`, pure, no Neovim API, yieldable by a plain loop):
  natural column width = widest cell by `text.width` (wide characters
  count 2); available = `ctx.width` minus `(ncols + 1)` borders minus
  `2 * ncols` cell padding. If the natural widths fit, use them; otherwise
  shrink proportionally with a per-column floor (the longest word of the
  column, capped to a small constant such as 8, then 1 as last resort) and
  distribute the remainder by largest fractional share. Cells wrap with
  `text.wrap_styled`; a word wider than its column hard-wraps. Row height =
  tallest cell; alignment uses `text.pad`. When even width-1 columns do not
  fit (`ctx.width < 3 * ncols + 1`) the table degrades to hard-wrapped
  plain pipe rows (`text.hard_wrap`), so no line ever exceeds the width.
  Algorithm is written here ("original" in `doc/references.md`).
- Box (`core/box.lua`): two glyph sets (`unicode`: light box-drawing
  with `┬ ┼ ┴ ├ ┤` junctions, `ascii`: `+ - |`) and a `rule(widths,
  position)` helper for top, header separator, row separator (none between
  body rows) and bottom borders. `ctx.charset` defaults to `unicode` until
  0018, same convention as `QUOTE_PREFIX`/`RULE_GLYPH` in `render.lua`;
  the ascii set is reachable now only through `ctx.charset = "ascii"` in
  tests.
- Render: the `table` handler in `document/render.lua` builds the cell
  fragments with the existing `flatten` (styles, link numbering through
  `ctx.links`), calls `core/table`, and emits border rows, header rows (
  `DocPreviewTableHeader`, `link = "Title"` fallback `Special`, plus bold)
  and body rows; borders carry `DocPreviewTableBorder` (`link =
  "Comment"`, `default = true`); cell spans are shifted to the cell's byte
  offset. Map entries: header rows -> `src_start`, top border and delimiter
  border -> header/delimiter lines (border rows map to the neighbouring
  source row, never unmapped), each body row's rows -> its source line
  (wrapped rows share it), bottom border -> last row. Required:
  entries are ascending and cover every output row.
- Pair projection (`tests/pairs/project_html.lua`): `<table>\n<thead>\n
  <tr>\n<th>..</th>\n</tr>\n</thead>\n<tbody>..</tbody>\n</table>\n` in
  `cmark-gfm` form, `align="left|center|right"` attribute only when set,
  no `<tbody>` when there are no body rows (verify exact whitespace against
  `cmark-gfm --extension table` on the host; unit tests pin the form
  chosen). Layout is not part of pair output.
- Oracle: `tools/oracle/commonmark-own` handles `gfm-table-*` before `gfm-*`
  with `--extension table` added (`strikethrough` and `tasklist` kept), so
  existing `gfm-*.expected` stay byte-identical; recorded in `.meta`.
  `cmark-gfm` is not in the sandbox, so the oracle task is host verify.
- Tables inside block quotes and list items work through the recursive
  `scan` (container prefix stripped); lazy continuation of table rows is
  not supported (a lazy line ends the table), recorded as a deliberate
  deviation only if the oracle disagrees.
- Size gates: `render.lua` 270 + table handler stays under 400; new files
  `markdown/table.lua`, `core/table.lua`, `core/box.lua` stay small.

## Tasks

- [x] 1. Pure primitives `core/box.lua` and `core/table.lua` (+ unit tests,
   new `tests/unit/box_spec.lua` and `tests/unit/table_spec.lua`). Box:
   glyph sets for unicode and ascii, border rule builder for the four
   positions. Table: `fit(natural, available, minimums)` column widths
   (natural when it fits, proportional shrink, floors, remainder
   distribution, sum never exceeds available), `wrap_cell(text, width,
   ranges)` via `text.wrap_styled`, row layout (height, padding, `text.pad`
   by alignment), degenerate-width fallback. Tests: fit (fits, shrink,
   floors, one column, many columns, exactly at limit, impossible width),
   wide CJK characters and combining marks counted by display width, a word
   longer than the column hard-wraps, alignment padding, empty cells, every
   produced line has display width <= width for a width sweep 1..40,
   both charsets.
- [x] 2. Model, highlight, renderer (+ unit tests). `document/model.lua`:
   `M.table` and `validate` cases (bad align value, ragged row, cell
   without `inlines`). `core/highlight.lua`: `DocPreviewTableHeader`,
   `DocPreviewTableBorder` (`tests/unit/highlight_spec.lua`).
   `document/render.lua`: `table` handler as in the decisions (cells via
   `flatten`, links numbered, spans shifted, map entries). Unit tests in
   `tests/unit/document_spec.lua` on hand-built trees: simple 2x2 exact
   output, alignments, empty cell, header only, narrow width wrapping cells
   with no row wider than `ctx.width`, wide characters, inline styles and
   link numbers inside cells, ascii charset via `ctx.charset`, tiny-width
   fallback, spans on header and borders, map entries (ascending, cover
   every row, wrapped rows share the source line), table inside a
   blockquote and a list item. `render.lua` stays under 400 lines.
- [x] 3. Pair projection for tables. `tests/pairs/project_html.lua` projects
   `table` to cmark-gfm HTML as in the decisions; extend
   `tests/unit/pairs_project_spec.lua` with hand-built cases (alignments,
   header only, escaped content, inline markup in cells, table in a
   quote). No parser change yet. Whitespace form (one tag per line,
   `normalize` makes it line-based) is unconfirmed: host check in task 9.
- [x] 4. Table parsing at top level (+ unit tests). New
   `markdown/table.lua`: `split_row(line)` (outer pipes, escaped pipes,
   trimming), `delimiter(line)` returning the alignment list or nil,
   `take_table(lines, linenos, k, header_text, ...)` collecting body rows
   until a blank line or another block start. `block.lua` `scan`: at a
   candidate delimiter line, check header cell count equality, split the
   open paragraph (earlier lines flush, header is the last chunk line) or
   use the previous line; emit pending `{ table = true, align, header,
   rows, start, last }`; `build` emits `model.table` with
   `inline.parse` per cell (refs shared); `collect_definitions` and
   `take_task_box` skip `table` entries; update header comments. Unit tests
   in `tests/unit/markdown_block_spec.lua` (or new
   `markdown_table_spec.lua`): basic table, no outer pipes, alignments
   (`:--`, `:-:`, `--:`), header/delimiter count mismatch is a paragraph,
   delimiter without a pipe is setext/thematic as before, ragged rows
   padded or truncated, escaped pipe, pipe in code span, inline markup and
   links in cells (reference definition resolved), empty cells, table
   interrupting a paragraph, table ended by blank line, by ATX, quote,
   fence, list; paragraph after table; ranges (`src_start`, `src_end`) at
   line > 1; `---` delimiter lookalikes (`| --- |` with one column needs
   a pipe). `block.lua` stays under 400 lines.
- [x] 5. Tables inside block quotes and list items (parser, unit tests).
   Verify the recursive `scan` handles stripped prefixes (ranges via
   `linenos`), a table row line in a quote or item continues the table,
   a lazy line does not (ends the table), a table ends with its quote or
   item (less-indented line), tight/loose detection (`is_tight` with a
   `table` entry using `start`/`last`), table in nested quote in list; fix
   `container.lua` only where a test shows a break (it is at 273 lines).
   Tests in `tests/unit/markdown_block_spec.lua`.
- [x] 6. Golden and integration. Golden fixtures
   `tests/golden/markdown/table-*.in|.out|.spans` at width 40 (generate
   with `UPDATE_GOLDEN=1 make test-golden`, review by hand): `table-basic`
   (alignments, inline styles, links), `table-wide` (shrink and cell wrap,
   CJK), `table-nested` (in quote and list item). Assert no line is wider
   than 40, header and border groups present. `tests/integration/
   table_spec.lua` (pattern of `html_spec.lua`): buffer with a table
   renders, no row exceeds the window width at several widths, border and
   header extmarks present, scroll/cursor mapping from each source row
   lands on its preview row and back, including a wrapped cell. Existing
   scroll and golden specs keep passing.
- [x] 7. Own pair inputs (host verify: oracle, see task 9). Done: 52 inputs, hand-verified through the projection (all match GFM behaviour, no parser bug found); oracle case added; `skip.lua` empty. Host: generate expectations (task 9). Write about 40
   fresh inputs `tests/pairs/markdown/own/gfm-table-*.in` (no spec text):
   basic, no outer pipes, alignment forms and mixes, single column,
   mismatch of header and delimiter counts, ragged rows, escaped pipe,
   pipe in code span, inline markup/links/entities in cells, empty cells
   and rows, header only, interrupting a paragraph, ended by blank line and
   by other blocks, text directly after, in quote and list item, indented
   1-3 spaces, 4-space indent as code, trailing spaces, delimiter with
   spaces around colons. Check every input by hand through the projection
   against GFM behaviour; without `.expected` the runner reports them
   pending. `tools/oracle/commonmark-own`: add a `gfm-table-*` case before
   `gfm-*` with `--extension table` added and recorded in `.meta`; update
   the header comment. Confirm `skip.lua` has no stale entry. (verified on host 2026-11-15)
- [x] 8. Docs. `doc/document-model.md` `table` row
   (cell shape, `src_start` + row mapping, rendered as box grid, header and
   border groups, colspan/rowspan unused for md); `doc/architecture.md`
   4.1 (header, delimiter and body rows map to their source rows, border
   rows to the neighbour, wrapped rows share), 6.1 (table detection
   rules, ragged rows, escaped pipes, interruption), 7 (new groups);
   `doc/references.md`: GFM "Tables (extension)" behaviour notes, state
   whether `markdown-it` (MIT) `table.js` patterns were ported (if so
   header comment in `markdown/table.lua` and a `NOTICE` entry), record
   the fitting algorithm as "original"; `doc/testing.md` section 2 notes
   `--extension table` for `gfm-table-*`; `doc/plan.md` row 0014 set to
   `in progress` when work starts and updated at the end (to `done` once
   tasks 9-10 pass on the host); this file's Status likewise.
- [x] 9. (host verify: oracle and pair baseline) Needs `cmark-gfm` with
   the table extension (`port install cmark-gfm`): `sh
   tools/oracle/commonmark-own` generates `gfm-table-*.expected`/`.meta`;
   confirm the diff shows no change to existing `.expected` files; confirm
   the projection whitespace chosen in task 3 matches (adjust
   `project_html.lua` if cmark-gfm differs); commit them. Then
   `make test-pairs`, triage failures (parser fix or `skip.lua` with reason,
   never hidden), raise `threshold.lua` `own` to the achieved pass count,
   record the table counts in `doc/references.md` (Pair baseline). (verified on host 2026-11-15)
- [x] 10. Final gates. In the sandbox: `agent-test --full` must pass and
   `make size banned` clean (400-line gate matters for `block.lua`,
   `render.lua`, `markdown/table.lua`, `core/table.lua`). (host verify:
   `make ci` for stylua and luacheck, `make format-check lint`, not
   installed in the sandbox). Order host-only work as 9 then 10 in one
   round-trip; then set `doc/plan.md` and this file's Status to `done`. (verified on host 2026-11-15)

## Done when

Pipe tables parse (alignment, ragged rows, escaped pipes), render as box
grids (unicode, ascii fallback) that fit `ctx.width` including wide
characters and wrapped cells, map row by row to the source, also inside
block quotes and list items; own pair inputs, goldens and integration specs
pass; `agent-test --full` passes and the quality gates are clean.
