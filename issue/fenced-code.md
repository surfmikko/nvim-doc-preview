# 0012 Fenced code

Status: done

Goal: fenced and indented code blocks render their lines verbatim with a
dim code highlight; no engine dispatch, no treesitter yet.

Touches: `markdown/block.lua` (fence open/close rules, info string,
indented code), `document/model.lua` (`code_block{lang,lines}`),
`document/render.lua` (verbatim lines), `core/highlight.lua`
(`DocPreviewCode`), `tests/pairs/project_html.lua` (`pre`/`code`,
`class="language-x"`), `doc/architecture.md` 4.1 (wording below).

Brings: backtick and tilde fences (length, indent stripping, unclosed
fence at end of document or container), info string to `lang`, indented
code blocks (assigned here: in `doc/architecture.md` 6.1 but in no roadmap
line), code inside block quotes and list items.
Decisions to take here: long code lines (clip with a marker or wrap; the
never-exceed-width rule of `doc/testing.md` 5 applies), and per-line map
entries for code (resolves `paragraph-real` note versus architecture 4.1
"code blocks map 1:1"; update 4.1 if the rule changes).

Tests: unit (`lang`, ranges, unclosed fence, indent stripping); own-input
pairs for "Fenced code blocks", "Indented code blocks" (cmark oracle);
golden; integration: scroll sync over code maps 1:1; width invariant.

References: CommonMark "Fenced code blocks", "Indented code blocks"
(behaviour only). Port: `markdown-it` (MIT) `fence.js`/`code.js` or
`cmark` (BSD-2). `doc/architecture.md` 4.1, 4.5 (lang kept on the node,
dispatch is later), 6.1, 7; `doc/document-model.md` (`code_block`).

Depends on: 0010, 0011 (containers), 0004 (highlight infrastructure).

Out of scope: engine dispatch for mermaid/dot/d2/plantuml, treesitter
highlight (`core/codeblock`), `core/errbox`.

## Decisions for the plan

- Model: `code_block{lang, lines}` plus `src_body` (source line of
  `lines[1]`: opening line + 1 for fences, `src_start` for indented code).
  Container-stripped lines are contiguous in the source, so the renderer maps
  `lines[i]` to source line `src_body + i - 1`; no per-line table needed.
  `doc/document-model.md` gains the field (task 8).
- Map rule: code maps 1:1 per line (architecture 4.1 stays as written; task 8
  only clarifies that each rendered row of a code line maps to that line's
  source line). The `paragraph-real` interpolation applies to paragraphs only.
- Long lines: hard-wrap at `ctx.width` by display width (no marker, no
  clipping, nothing lost, never exceeds width); continuation rows map to the
  same source line. Wrapping helper goes in `core/text.lua` if it is not
  already there (with unit tests); the coder may switch to clip-with-marker
  only if wrapping proves unworkable, and records why in the task note.
- Render: no prefix or box; lines verbatim (no trailing-blank trimming, tabs
  expanded to spaces so width is exact), whole block gets a
  `DocPreviewCode` span per non-empty row. `lang` is not shown. Blank line
  between blocks as usual.
- Parser code goes into a new `markdown/code.lua` (fence open/close rules,
  indented-code run collection, info string), injected the same way as
  `container.lua`; `block.lua` (220 lines) and `container.lua` (257) must stay
  under the 400-line gate, `render.lua` is 236.
- Pending entry `{ code = true, fenced, lang, lines, start, last, body }`.
  `collect_definitions` skips it (like rules/headings); `build` emits
  `model.code_block`. `scan` returns `open = false` after a code block, so a
  fence or indented code is never lazily continued.
- Un-skip as soon as the producing task makes a case pass (a stale skip fails
  the run): `own/atx-indent-4`, `own/atx-tab-indent`, `own/thematic-indent-4`,
  `own/paragraph-four-spaces`, `own/quote-indent-4`, `own/quote-fence-inside`,
  `own/list-fence-inside`, `own/list-indented-code-5-spaces`,
  `own/list-indented-code-inside` in `tests/pairs/markdown/skip.lua`. Check each
  by hand through the projection; one that still fails for another reason stays
  skipped with the new reason.

## Tasks

- [x] 1. Model, renderer, highlight (+ unit tests). `document/model.lua`:
   `M.code_block(lang, lines, src_body, src_start, src_end)` (register the kind,
   `validate` checks `lines` is a table of strings). `document/render.lua`:
   `code_block` handler per the decisions above (verbatim rows, tab expansion,
   hard-wrap at `ctx.width` with min 1, empty block renders one empty row,
   one map entry per source line `src_body + i - 1`, wrapped rows share it;
   `DocPreviewCode` span on non-empty rows). Add a `core/text` display-width
   hard-wrap helper with unit cases (wide chars, exact fit, width 1) if none
   fits. `core/highlight.lua` already defines `DocPreviewCode`; confirm in
   `tests/unit/highlight_spec.lua`. Unit tests in
   `tests/unit/document_spec.lua` on hand-built trees: plain, empty,
   blank lines inside, long line wraps and no row exceeds width, tabs, unicode,
   map entries (1:1, wrapped rows), inside a blockquote and a list item (prefix
   and hanging indent applied, width reduced), tiny width, spans. Existing
   specs keep passing.
- [x] 2. Pair projection for code. `tests/pairs/project_html.lua` projects
   `code_block` to `<pre><code>` with `class="language-<lang>"` only when
   `lang` is non-empty, HTML-escaped body (`& < > "`), each line ends in `\n`,
   empty block is `<pre><code></code></pre>`; code inside a tight list item has
   no `<p>` concerns. Extend `tests/unit/pairs_project_spec.lua` with
   hand-built cases (lang, no lang, escapes, empty, in quote, in tight and loose
   item). No parser change yet.
- [x] 3. Fenced code in the parser, top level (+ unit tests). New
   `markdown/code.lua` with fence open (0-3 columns of indent, 3+ backticks or
   tildes, backtick info string may not contain a backtick), close (same
   char, at least as long, 0-3 indent, only trailing blanks), indent stripping
   up to the opener's indent, unclosed fence runs to the end of the scanned
   lines (document or container), info string to `lang` (first word, backslash
   and entity unescaped via `markdown/unescape`/`entities`, empty to `nil`).
   `scan` in `block.lua` checks the fence opener before setext/thematic and
   treats every line until the close as raw (no ATX, setext, quote, list,
   definition handling inside); a fence interrupts a paragraph; add the
   `code` pending entry, `collect_definitions`/`build` cases, update header
   comments. `scan` reports `open = false` after code. Unit tests in
   `tests/unit/markdown_block_spec.lua`: backtick and tilde fences, length 4+,
   closing shorter does not close, other char does not close, closing with
   indent 0-3 vs 4, info string with lang plus attributes, empty info, backtick
   in backtick info is not a fence (paragraph), tilde info with backtick is ok,
   indent stripping 1-3, 4 spaces is not a fence, unclosed at end, empty fence,
   blank lines inside, `# `, `---`, `> ` and `- ` lines inside stay raw,
   interrupts a paragraph, setext-like `---` after paragraph then fence,
   source ranges (`start`, `last`, `src_body`) at line > 1, reference
   definition-looking line inside a fence is not a definition. Remove no skip
   here (containers come in task 5). Both files stay under 400 lines.
- [x] 4. Indented code in the parser (+ unit tests). In `markdown/code.lua`:
   a line with 4+ columns of indent (tab stop 4, shared `expand_indent`)
   that cannot interrupt a paragraph (only starts after a blank line or at
   block start; when a paragraph is open it stays a paragraph continuation as
   today), run collected through blank lines that are followed by more indented
   lines, 4 columns stripped (partial tab handled like `strip_columns`),
   trailing blank lines dropped from the block and its source range, interior
   blanks kept. Precedence in `scan`: blank, fence, indented code (before ATX,
   setext, thematic, quote and list tests, since those all need indent <= 3).
   Unit tests in `tests/unit/markdown_block_spec.lua`: 4 spaces, tab, 5 spaces
   keeps extra, blank lines inside kept and trailing dropped, ends at an
   unindented line, after a paragraph is not code (continuation), after a
   heading and after a rule is code, `#`/`-`/`>` after 4 spaces is code text,
   ranges at line > 1, definition-looking line stays text. Un-skip
   `own/atx-indent-4`, `own/atx-tab-indent`, `own/thematic-indent-4`,
   `own/paragraph-four-spaces` when they pass.
- [x] 5. Code inside block quotes and list items (parser, unit tests,
   un-skips). `markdown/container.lua`: no new nesting logic expected since
   inner lines go through `scan`; verify and fix the places that look at raw
   lines: `take_quote` break test (`atx`/`thematic`/`item_marker` must not
   end a quote or lazily match on a line that is inside an open fence; a
   fenced or indented code block is never lazily continued), `ends_item`,
   `take_item` blank-line handling (blank lines inside a fence in an item, a
   fence unclosed when the item ends, less-indented line closes the item and
   so the fence), `is_tight` (blank lines inside a code block do not loosen
   a list; use code `start`/`last` so trailing blanks of an unclosed fence
   are not counted), item content-column rule (`-     a` 5 spaces is an
   item starting with indented code, content column marker+1), `1. ```` same
   line. Unit tests in `tests/unit/markdown_block_spec.lua`: fence in quote
   (closed, unclosed, ends with the quote, lazy line is not code), indented
   code in quote (`>     a`), fence in item, fence at 2-space indent in item
   with stripping, blank line inside fence in item, item ends mid-fence,
   indented code in item (after blank, 4 spaces beyond content column),
   5-space marker item, fence in nested item, quote inside item holding a
   fence, tight list with fence stays tight, loose by blank before fence,
   ranges at every level, no crash on a fence in a quote in a list. Un-skip
   `own/quote-indent-4`, `own/quote-fence-inside`, `own/list-fence-inside`,
   `own/list-indented-code-5-spaces`, `own/list-indented-code-inside`.
- [x] 6. Golden and integration. Golden fixtures
   `tests/golden/markdown/code-*.in|.out|.spans` at width 40 (generate with
   `UPDATE_GOLDEN=1 make test-golden`, review by hand): `code-fenced`
   (backtick, tilde, lang, unclosed, long line wrapping, empty fence, blank
   lines inside), `code-indented` (plain, blank lines, after heading, tab),
   `code-nested` (fence in quote, in bullet and ordered item, indented code
   in item, quote in item with a fence, code in nested list). Check no line is
   wider than 40 and the `DocPreviewCode` span covers every non-empty code row.
   `tests/integration/code_spec.lua` (pattern of `lists_spec.lua`): buffer
   with a fenced block, an indented block, and a fence inside a quote and a
   list renders; no row exceeds the window width; scroll/cursor mapping from a
   source line inside a code block lands on the matching preview row and back
   1:1, including a wrapped long line (all its rows map to the one source
   line). Existing scroll and golden specs keep passing.
- [x] 7. Own pair inputs (host verify: oracle, see task 9). Done in the sandbox: 104 inputs `own/code-{fence,indented,quote,list,precedence}-*.in`, each checked by hand through the projection against CommonMark behaviour; no `.expected` yet (reported pending). `skip.lua` is empty (all nine un-skipped earlier). Hand-check found a parser bug, fixed: an unindented fence opener was lazily continuing a quote/item paragraph; `container.lua` now ends the quote/item on `fence_open` (injected via `setup`), with two unit tests.
   Write about 40 fresh inputs `tests/pairs/markdown/own/code-*.in` (no spec
   text; skip names already present): backtick and tilde fences, length 4/5,
   closer shorter or other char, closer longer, indent 1-3 stripping, 4 spaces,
   info string forms (lang, lang plus attrs, entity/backslash in info, backtick
   in backtick info, tilde info with backtick), empty fence, unclosed at end,
   fence interrupting a paragraph, paragraph after fence closer, markdown
   syntax inside fence (`#`, `---`, `>`, `-`, refs), blank lines inside and
   around, `&`/`<` escaping in body, indented code (4 spaces, tab, 5 spaces,
   blank interior, trailing blanks, after paragraph is not code, after heading,
   after rule), fence in quote (closed, unclosed, lazy line), indented code in
   quote, fence in bullet and ordered item (with content column indent, less
   indent closing), indented code in item, code in nested item, plus
   "Precedence" entries. Check every input by hand through the projection;
   without `.expected` the runner reports them pending. Confirm no stale or
   missing `skip.lua` entries (all nine listed in the decisions are removed
   or re-justified). (verified on host 2026-11-15)
- [x] 8. Docs. `doc/document-model.md` `code_block` row: `src_body`, verbatim
   rendering, wrap rule, `DocPreviewCode`; `doc/architecture.md` 4.1
   (code maps 1:1 per source line, wrapped rows share it), 4.2/6.1 (fence
   rules, indented code, never lazily continued; indented code added to
   6.1 if missing), 4.5 unchanged except a note that 0012 renders every
   `lang` as plain code until `core/codeblock`; `doc/references.md` gets the
   CommonMark "Fenced code blocks", "Indented code blocks" behaviour notes and
   states whether code was ported (if `markdown-it`/`cmark` code was used, add
   a header comment and a `NOTICE` entry); `doc/plan.md` row 0012 set to
   `in progress` (to `done` once tasks 9-10 pass on the host); this file's
   Status likewise.
- [x] 9. (host verify: oracle and pair baseline) Needs `cmark` and
   `cmark-gfm` (`port install cmark cmark-gfm`): `sh tools/oracle/commonmark-own`
   generates `code-*.expected`/`.meta`; confirm existing `.expected` are
   unchanged by the diff and the formerly skipped nine pass; commit them.
   Then `make test-pairs`, triage failures (parser fix or `skip.lua` with
   reason, never hidden), raise `threshold.lua` `own` to the achieved pass
   count, record the code counts in `doc/references.md` (Pair baseline). (verified on host 2026-11-15)
- [x] 10. Final gates (host verify: `make ci` for stylua/luacheck if not
   installed in the sandbox): `agent-test --full` must pass; run
   `make format-check lint size banned` where runnable (the 400-line gate
   matters for `block.lua`, `container.lua`, `code.lua`, `render.lua`,
   `text.lua`). Order host-only work as 9 then 10 in one round-trip; then set
   `doc/plan.md` and this file's Status to `done`. Sandbox: `agent-test --full` passes, `make size banned` clean; stylua/luacheck not installed, left for `make ci` on the host. (verified on host 2026-11-15)

## Done when

Fenced (backtick, tilde, unclosed) and indented code blocks, also inside
block quotes and list items, render verbatim with `DocPreviewCode`, wrapped to
the width, mapping 1:1 to source lines; the nine skipped pair inputs pass or
are re-justified; goldens and integration specs pass; `agent-test --full`
passes and the quality gates are clean.
