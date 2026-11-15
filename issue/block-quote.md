# 0010 Block quote

Status: done

Goal: `>` blocks render with a quote prefix, nested quotes and lazy
continuation lines work, and width includes the prefix.

Touches: `markdown/block.lua` (container machinery, shared with lists in
0011; split into modules if the 400-line gate bites), `document/model.lua`
(`blockquote`), `document/render.lua` (prefix per line, children rendered
with `ctx.width` minus prefix), `core/text.lua` (prefix-aware wrap),
`core/highlight.lua` (quote group), `tests/pairs/project_html.lua`
(`blockquote`).

Brings: container-block continuation algorithm (open containers matched per
line, lazy paragraph continuation), source ranges for children inside a
container, nested block-quote rendering.

Tests: unit (container nesting, lazy continuation, ranges, blank line
ending a quote); own-input pairs for "Block quotes", "Container blocks and
leaf blocks", "Precedence" (cmark oracle); golden; no line exceeds width;
scroll specs.

References: CommonMark "Block quotes", "Container blocks and leaf blocks",
"Precedence" (behaviour only). Port: `commonmark.js` (BSD-2) block
continuation or `markdown-it` (MIT) `blockquote.js`; record in
`doc/references.md`/`NOTICE`. `doc/architecture.md` 4.2, 4.3 (hanging/prefix
indent, width includes prefix), 6.1; `doc/document-model.md` (`blockquote`).

Depends on: 0006 (inlines in quoted paragraphs), 0009 (rule precedence).

Out of scope: lists inside quotes (0011), fenced code inside quotes (0012).

## Tasks

- [x] 1. Model and renderer: `document/model.lua` gains
   `M.blockquote(children, src_start, src_end)` (kind registered,
   `validate` recurses through `children`). `core/out.lua` gains a small
   `prefix(frag, str, group)` helper (or equivalent in `render.lua` if
   `out.lua` should stay untouched) that prepends `str` to every line of a
   fragment, shifts span columns and keeps map entries. `document/render.lua`
   gains a `blockquote` handler: render the children with `ctx.width`
   reduced by the prefix width (min 1; copy of ctx, `ctx.links` shared),
   separate children with a blank line, prefix every line including the
   blank ones (so the bar is continuous), one map entry per child shifted
   unchanged (children already carry real source lines), whole-quote map
   entry only for an empty quote. Prefix glyph is a local constant
   (unicode `│ `, comment pointing to 0018 for ascii `| `); the prefix gets
   the `DocPreviewQuote` span. The top-level loop and the quote handler
   share one `render_blocks(children, ctx)` so nesting recurses.
   `core/highlight.lua` defines `DocPreviewQuote` (link to `Comment`,
   `default = true`) and `tests/unit/highlight_spec.lua` covers it.
   Unit tests in `tests/unit/document_spec.lua` on hand-built trees: single
   paragraph, wrapped paragraph (every line prefixed, none wider than
   width), two children, nested quote (width shrinks per level), prefix
   span, map entries, tiny width.
- [x] 2. Container machinery in the block parser (`markdown/block.lua`,
   split to `markdown/container.lua` if the 400-line gate bites; `block.lua`
   is 169 lines now). Refactor `parse` so line-to-block scanning is a
   function over `(lines, linenos)` returning `pending` entries, where
   `linenos[k]` is the source line of inner line k (identity at top level).
   This keeps every `src_start`/`src_end` a real source line for children
   inside a container. Add a `quote` pending entry holding nested
   `pending` children; `collect_definitions` and `build` recurse into it,
   sharing one `refs` table (a definition inside a quote is visible to the
   whole document, a reference before it still resolves). Quote detection:
   up to 3 columns of indent then `>`, one optional following space (a tab
   after `>` counts as the optional space and expands the rest; handle
   with `expand_indent` columns). Algorithm: a quote starts at a `>` line;
   strip the marker from consecutive lines; a line with a marker continues
   the quote; a non-blank line without a marker is a lazy continuation only
   if the last open inner block is paragraph text (an open paragraph, i.e.
   `start` set after inner scanning of the lines so far) and the line would
   not itself start a block (ATX, thematic break, another `>`; setext
   underline `===`/`---` lazy lines are plain text per CommonMark, so the
   `---` case is a rule/not an underline of the quoted paragraph: decide by
   hand against the spec, one unit test each); a blank line (or one with
   only `>`) ends lazy continuation, and a blank line without `>` ends the
   quote. Inner lines are parsed recursively by the same function so nested
   `> >` works with no special case. A `>` line interrupts an open
   paragraph. Order of tests per line: blank, ATX, setext underline, thematic
   (0009 precedence kept: `> ---` inside a quote is a rule in the quote),
   then quote start. Lists and fenced code inside quotes stay paragraph
   fallback (0011/0012) and must not crash. Update the file header comment.
   `tests/unit/markdown_block_spec.lua`: single and multi-line quote, `>`
   with and without space, indent 0-3 vs 4 (4 is paragraph fallback), empty
   `>` line inside a quote splits paragraphs, blank line ends the quote
   and starts a new one (`>a\n\n>b` is two quotes), lazy continuation
   (`> a\nb`), lazy line does not continue after a heading or rule inside
   the quote, `> a\n---` is quote then rule, `> a\n# b` closes the quote,
   nested `> > a`, `>> a`, lazy through two levels, quote interrupting a
   paragraph, heading/paragraph/rule inside a quote, source ranges of the
   quote and of each child (including lazy lines and a quote that starts
   at line > 1), link reference defined inside a quote and used outside,
   no crash on `> - a` and ``> ``` ``. Existing specs (headings, thematic
   break, scroll integration) keep passing.
- [x] 3. End to end wiring: confirm `session`/`init` render path needs no
   change (the renderer handles `blockquote`); golden fixtures
   `tests/golden/markdown/blockquote.in|.out|.spans` at width 40 (single
   quote with long wrapped paragraph, two paragraphs in one quote, nested
   two levels, lazy continuation, quote with heading and rule inside, quote
   with inline emphasis and a link, empty `>` line, quote between
   paragraphs); generate with `UPDATE_GOLDEN=1 make test-golden` and review
   the diff by hand (no line wider than 40, prefix span on every line,
   link marker numbering unchanged). Add an integration spec
   `tests/integration/blockquote_spec.lua` (pattern of
   `paragraph_wrap_spec.lua`): a buffer with a quote renders in the preview
   window, no rendered line exceeds the window width, and cursor/scroll
   mapping from a source line inside the quote (including a lazy line)
   lands on the matching preview line and back. Existing scroll specs keep
   passing.
- [x] 4. Pair projection and own inputs: `tests/pairs/project_html.lua`
   projects `blockquote` to `<blockquote>`, newline, children, newline,
   `</blockquote>` (cmark's form; empty quote is `<blockquote>\n</blockquote>`;
   `normalize` unchanged, check it handles the nested output). Extend
   `tests/unit/pairs_project_spec.lua` with hand-built and parsed cases
   (`> a`, nested, lazy, quote then paragraph, `> # h`). Write about 25
   fresh inputs `tests/pairs/markdown/own/quote-*.in` (no spec text):
   simple, no space after `>`, multi-line, lazy continuation, lazy after
   blank-`>` (not lazy), blank line splits quotes, nested, `>>` nested,
   lazy through nesting, empty `>`, indent 1-3, indent 4 (skip: indented
   code), heading/rule/paragraph inside, quote interrupting a paragraph,
   ATX/rule closing a quote, setext-looking line after a quoted paragraph,
   tab after `>`, emphasis and link inside, reference definition inside a
   quote used outside, plus a few for "Container blocks and leaf blocks" and
   "Precedence" (`- a`/` > b` mixes are skipped until 0011: `lists: 0011`,
   `fenced code: 0012` with reasons in `tests/pairs/markdown/skip.lua`).
   Check every input by hand against the expected HTML via the projection;
   `tools/oracle/commonmark-own` should pick up the new `.in` files
   unchanged (verify). Without `.expected` the runner reports them pending
   and the suite passes.
   Done: projection, unit specs, 32 `own/quote-*.in` (4 skipped in
   `skip.lua`: indent-4, list-inside, fence-inside, list-mix).
   Host check (`cmark` missing in sandbox): `sh tools/oracle/commonmark-own`
   generates `quote-*.expected`/`.meta` (the script globs `*.in`, no change
   needed); expected HTML for the empty quote is `<blockquote>\n</blockquote>`. (verified on host 2026-11-15)
- [x] 5. Reference notes: add the CommonMark "Block quotes", "Container
   blocks and leaf blocks" and "Precedence" behaviour notes to
   `doc/references.md` (behaviour only; if code was ported from
   `commonmark.js` or `markdown-it`, add a header comment in the ported
   file and a `NOTICE` entry, otherwise state that none was); add the
   rendering (prefix glyph until 0018, width minus prefix, nested quotes) to
   the `blockquote` note in `doc/document-model.md` and the container
   continuation algorithm summary to `doc/architecture.md` 4.2 or 6.1 if not
   already implied. Set Status to `in progress` while tasks 6-7 are open.
- [x] 6. Pair baseline (host verify: needs `cmark`): `port install cmark`;
   `sh tools/oracle/commonmark-own`; commit the new
   `.expected`/`.meta` files; `make test-pairs`; triage every failure (fix
   the parser or add a `skip.lua` entry with a reason; deviations are
   reviewed, not hidden); raise `threshold.lua` `own` to the achieved pass
   count; record the block-quote counts in `doc/references.md` if it keeps
   per-section counts. (verified on host 2026-11-15)
- [x] 7. Final gates: run `agent-test --full` (must pass) and the stylua and
   luacheck gates where runnable (`make format-check lint size banned`; the
   400-line size gate matters for `block.lua`). If stylua or luacheck are
   missing in the sandbox, mark `(host verify: make ci)`. After task 6
   passes on the host, set Status to `done` and update the
   `doc/plan.md` row.
   Result: `agent-test --full` passes; `make size banned` pass; stylua and
   luacheck are not installed in the sandbox (host verify: `make ci`). (verified on host 2026-11-15)

## Done when

`>` blocks render with a quote prefix, nested quotes and lazy continuation
lines work, no rendered line exceeds the width (prefix included),
source/preview mapping works inside quotes, `agent-test --full` passes, and
the quality gates are clean.
