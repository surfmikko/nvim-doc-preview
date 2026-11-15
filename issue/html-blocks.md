# 0013 HTML blocks

Status: done

Goal: HTML blocks and inline raw HTML render verbatim and dimmed.

Touches: `markdown/block.lua` (seven start conditions and their end
conditions), `markdown/inline.lua` (`md:html_inline`), `document/model.lua`
(`md:html_block`, `md:html_inline`), `document/render.lua`,
`core/highlight.lua` (dim group), `tests/pairs/project_html.lua` (raw HTML
passthrough), `doc/references.md`.

Brings: inline raw HTML is in the model and in `doc/architecture.md` 6.1
but in no earlier roadmap line, so it is assigned here (block start/end
conditions, tags, comments, processing instructions, declarations, CDATA;
inline tags, comments). GFM "Disallowed Raw HTML" is behaviour only for
the projection and is not rendered differently.

Tests: unit; own-input pairs for "HTML blocks", "Raw HTML" (cmark oracle);
golden; width invariant for long lines (same decision as 0012).

References: CommonMark "HTML blocks", "Raw HTML"; GFM "Disallowed Raw HTML
(extension)" (behaviour only). Port: `markdown-it` (MIT) `html_block.js`,
`html_inline.js`, `html_re.js` or `commonmark.js` (BSD-2).
`doc/document-model.md` (`md:html_block`, `md:html_inline`);
`doc/architecture.md` 2, 6.1.

Depends on: 0011 (blocks inside containers), 0006 (inline parser).

Out of scope: any HTML interpretation or rendering.

## Decisions for the plan

- Model: `md:html_block{lines}` plus `src_body` (same convention as
  `code_block`: source line of `lines[1]`; lines are contiguous in the source,
  so row `i` maps to `src_body + i - 1`, no per-line table). `md:html_inline`
  has `value` and no range. Both register in `document/model.lua`
  (`kinds`/`inline_kinds`, `validate`: `lines` table of strings, `value`
  string).
- Block lines are verbatim: container prefix stripped (inner lines from
  `scan`), but leading indent (0-3 columns) is kept, nothing trimmed.
- Render: `md:html_block` reuses the code-block row logic (tab expansion,
  hard-wrap at `ctx.width`, one map entry per source line, wrapped rows share
  it, empty block renders one empty row): factor the existing `code_block`
  body in `document/render.lua` into one local helper taking the highlight
  group, so there is no duplicated wrapping. Group is the new `DocPreviewHtml`
  (`link = "Comment"`, `default = true`) in `core/highlight.lua`. Inline
  `md:html_inline` is plain text of `value` inside the paragraph flow with a
  `DocPreviewHtml` range (`GROUPS` table in `flatten`); wrapping is the
  paragraph's. No handler fallback (`unsupported`) must remain for either kind.
- Parser code goes into a new `markdown/html.lua` (block start/end
  conditions 1-7 and the inline raw-HTML matchers), injected into `container`
  like `fence_open`. Size gates: `block.lua` 236, `container.lua` 265,
  `inline.lua` 360 lines (400 limit), so `inline.lua` only gains a short
  `<` handler call and all patterns live in `html.lua`.
- Block rules (behaviour from the CommonMark "HTML blocks" section): 0-3
  columns indent; start conditions 1 (`<script|pre|style|textarea`, ends at a
  line containing the matching closing tag, case-insensitive), 2 (`<!--`, ends
  at `-->`), 3 (`<?`, `?>`), 4 (`<!` + letter, `>`), 5 (`<![CDATA[`, `]]>`),
  6 (block-level tag name list, opening or closing, followed by space, tab,
  EOL, `>` or `/>`; ends before the next blank line), 7 (a complete open or
  closing tag alone on the line, tag name not in 1; ends before the next blank
  line). 1-6 may interrupt a paragraph; 7 may not. Ends 1-5 include the line
  holding the end marker (a start line may also hold it). An unclosed block
  runs to the end of the document or container. Never lazily continued
  (`scan` returns `open = false` after it). Contents are never parsed (no
  ATX, setext, quote, list, definition, fence inside).
- Inline rules (CommonMark "Raw HTML"): open tag with attributes (name, value
  forms unquoted/single/double, line breaks allowed in whitespace), closing
  tag, comment (`<!-->`, `<!--->`, `<!-- ... -->`), processing instruction,
  declaration, CDATA. A match becomes one atomic `md:html_inline` node;
  emphasis delimiters do not cross it but inner text is not parsed. Tried
  after autolink in the `<` handler; a code span wins because its backtick
  comes first in the scan. Newlines inside the value
  render as spaces (existing `leaf_text`).
- GFM "Disallowed Raw HTML" is not rendered differently: no tagfilter.
- Pair projection: `md:html_block` projects to its lines verbatim (no
  escaping) each ending in `\n`; `md:html_inline` to its `value` verbatim.
  cmark only passes raw HTML through with `--unsafe` (0.29.0+: default
  replaces it by `<!-- raw HTML omitted -->`): `tools/oracle/commonmark-own`
  gets `--unsafe` for inputs named `html-*` only, recorded in `.meta`, so
  existing `.expected` files stay byte-identical.
- Skips: check `tests/pairs/markdown/skip.lua` (currently empty) and every
  existing own input containing `<` for changed behaviour (autolink-like
  text, `<` literals); a regression there is fixed, not skipped.

## Tasks

- [x] 1. Model, renderer, highlight (+ unit tests). `document/model.lua`:
   `M.html_block(lines, src_body, src_start, src_end)` (kind `md:html_block`)
   and `M.html_inline(value)` (kind `md:html_inline`, listed in
   `inline_kinds`), `validate` cases. `core/highlight.lua`: `DocPreviewHtml`.
   `document/render.lua`: factor the `code_block` row logic into one helper
   parameterised by group, register `md:html_block` with `DocPreviewHtml`;
   add `md:html_inline` to `GROUPS` in `flatten` (text of `value`, so
   `leaf_text` already works). Unit tests in `tests/unit/document_spec.lua`
   on hand-built trees: block plain, empty, blank lines inside, indent kept,
   long line wraps and no row exceeds width, tabs, unicode, map entries (1:1,
   wrapped rows share), inside a blockquote and a list item, tiny width,
   `DocPreviewHtml` span on non-empty rows only; inline value in a paragraph
   (span range, wraps with surrounding text, newline in value becomes a
   space, adjacent to emph); `validate` rejects bad `lines`/`value`;
   `tests/unit/highlight_spec.lua` checks the group. Existing code-block
   specs keep passing unchanged.
- [x] 2. Pair projection for HTML. `tests/pairs/project_html.lua` projects
   `md:html_block` (lines verbatim, no escaping, each ending in `\n`, in a
   tight list item no `<p>` concerns) and `md:html_inline` (value verbatim,
   inside paragraphs/headings/emphasis). Extend
   `tests/unit/pairs_project_spec.lua` with hand-built cases (block at top
   level, in quote, in tight and loose item, inline in paragraph and in
   emphasis, `&`/`<` untouched). No parser change yet.
- [x] 3. HTML blocks in the parser, top level (+ unit tests). New
   `markdown/html.lua`: `block_start(line, para_open)` returning the
   condition 1-7 (nil when indent > 3, or condition 7 while a paragraph is
   open) and `block_end(line, kind)` for 1-5. Condition 6 uses the CommonMark
   block-tag-name list and requires a delimiter after the name; condition 7
   needs a complete tag (write the open/closing-tag matcher here as a shared
   function; task 5 reuses it for inline tags).
   `take_html(lines, linenos, k, kind)` collects verbatim lines, 1-5 through
   the line with the end marker (start line included, also when it holds the
   marker), 6-7 up to but excluding the next blank line, unclosed to the end
   of the scanned lines; returns pending entry
   `{ html = true, lines, start, last, body }` and the next index. `scan` in
   `block.lua`: check the start after blank and fence/indented-code tests and
   before ATX/setext/thematic/quote/list (an HTML start line with 0-3 indent
   wins over those); 1-6 interrupt a paragraph (flush), 7 does not; set
   `open = false` after the block; `build` emits `model.html_block`;
   `collect_definitions` and `take_task_box` skip `html` entries; update
   header comments. Unit tests in `tests/unit/markdown_block_spec.lua`: each
   condition 1-7 start and end (including multi-line `<pre>`, comment, PI,
   declaration, CDATA, end marker on the start line, case-insensitive tag
   names), end tags and self-closing forms for 6, condition 7 with attributes
   and a complete tag only (partial tag or trailing text is a paragraph),
   7 not interrupting a paragraph but 1-6 doing so, 4 spaces is indented code
   not HTML, blank line inside 1-5 does not end, ends 6-7 at blank,
   `# `/`---`/`> `/`- `/fence/reference definition inside stay raw,
   unclosed at end, ranges (`start`, `last`, `src_body`) at line > 1, and the
   paragraph after the block starting normally. `block.lua` and `html.lua`
   stay under 400 lines.
- [x] 4. HTML blocks inside block quotes and list items (parser, unit
   tests). `markdown/container.lua`: inject `html.block_start` through
   `setup` (like `fence_open`) and fix the raw-line tests: `take_quote` and
   `take_item` lazy-continuation checks must end the quote or item on an
   unindented line that starts an HTML block of conditions 1-6 (not 7), and
   an HTML block is never lazily continued; `ends_item`/`take_item` blank-line
   handling (blank lines inside an unclosed condition 1-5 block within an
   item, less-indented line closes the item and the block); `is_tight` (blank
   lines inside an html block do not loosen a list, use the entry `start` and
   `last`); condition 6/7 block ends at the blank line that precedes the
   container's next content. Unit tests in
   `tests/unit/markdown_block_spec.lua`: block in quote (closed, unclosed,
   ends with the quote, lazy line is not part of it, `>` prefix stripped,
   leading indent kept), in bullet and ordered item (content column indent,
   less indent closes), comment with blank lines inside an item, nested item
   and quote-in-item, tight list with html block stays tight, loose by blank
   before it, ranges at every level, no crash on html in a quote in a list.
   Check `tests/pairs/markdown/skip.lua` stays consistent.
- [x] 5. Inline raw HTML (parser, unit tests). `markdown/html.lua`:
   `inline_match(s, i)` returning the matched raw string or nil for an open
   tag (tag name, attributes with the three value forms, `/` self-close,
   whitespace including newlines, no `<` or backtick-spanning surprises),
   closing tag, comment (`<!-->`, `<!--->`, `<!--...-->`), processing
   instruction, declaration, CDATA. `markdown/inline.lua`: in
   `handlers["<"]` try the autolink first, then `html.inline_match`, push
   `model.html_inline(raw)` and advance; else `<` stays text. Keep
   `inline.lua` under 400 lines. Unit tests (new
   `tests/unit/markdown_html_spec.lua` for the matcher, additions to the
   inline spec for the integration): each form, attribute value forms,
   invalid names or unterminated forms stay text, newline inside a tag,
   autolink still wins for `<http://x>`/`<a@b.co>`, tag inside emphasis
   (`*a <b> c*`), delimiter runs not matched across the node, tag inside a
   link text, tag inside a code span stays code text, entity in an attribute
   untouched, backslash before `<` escapes it. Existing inline, links and
   pair specs keep passing.
- [x] 6. Golden and integration. Golden fixtures
   `tests/golden/markdown/html-*.in|.out|.spans` at width 40 (generate with
   `UPDATE_GOLDEN=1 make test-golden`, review by hand): `html-blocks` (each
   condition, multi-line `<div>`, comment with blank lines, `<pre>` block,
   html then paragraph then html, long line wrapping), `html-inline` (tags,
   comment, inline in wrapped paragraph and heading), `html-nested` (block in
   quote, in bullet and ordered item, in nested list). Check no line is
   wider than 40 and `DocPreviewHtml` covers every non-empty html row and
   each inline range. `tests/integration/html_spec.lua` (pattern of
   `code_spec.lua`): buffer with an html block, inline html, and html in a
   quote and a list renders, no row exceeds the window width, `DocPreviewHtml`
   extmarks present, scroll/cursor mapping from a source line in a multi-line
   html block lands on the matching preview row and back 1:1 including a
   wrapped long line. Existing scroll and golden specs keep passing.
- [x] 7. Own pair inputs (host verify: oracle, see task 9). Write about 60
   fresh inputs `tests/pairs/markdown/own/html-*.in` (no spec text; skip
   names already present): per start condition 1-7 (start, end, end on the
   same line, case variants, `<pre>` with blank lines, `<style>`/`<script>`
   content with markdown-looking lines, comment forms, PI, declaration,
   CDATA), condition 6 tag names and delimiter forms (`<div>`, `<div/>`,
   `</div>`, `<divx>` is not 6, `<div` at EOL), condition 7 (complete tag
   with attributes, partial tag, text after tag, closing tag alone, cannot
   interrupt a paragraph), interrupting a paragraph (1-6), 4-space indent is
   code, 1-3 space indent kept, markdown syntax inside, blank-line endings,
   html in quote (closed, unclosed, lazy line), in bullet and ordered item,
   nested, tight/loose lists, inline raw html (tags, attributes forms,
   comment forms, PI, declaration, CDATA, newline in tag, invalid forms,
   inside emphasis, inside link text, inside code span, escaped `<`,
   autolink precedence). Check every input by hand through the projection
   against CommonMark behaviour; without `.expected` the runner reports them
   pending. In `tools/oracle/commonmark-own` add `--unsafe` to the `cmark`
   call for `html-*` inputs only and record it in the `.meta` command line.
   Confirm `skip.lua` has no stale or missing entry. (verified on host 2026-11-15)
- [x] 8. Docs. `doc/document-model.md` rows for `md:html_block` (add
   `src_body`, verbatim, indent kept, wrap rule, `DocPreviewHtml`) and
   `md:html_inline` (atomic node, `DocPreviewHtml`); `doc/architecture.md`
   4.1 (html block maps 1:1 per source line, wrapped rows share it), 6.1
   (seven start/end conditions, 7 cannot interrupt a paragraph, never lazily
   continued, inline forms, no tagfilter); `doc/references.md` gets the
   CommonMark "HTML blocks" and "Raw HTML" behaviour notes and the GFM
   "Disallowed Raw HTML" note (not rendered differently), and states whether
   `markdown-it` (MIT) or `commonmark.js` (BSD-2) patterns were ported (if
   so, header comment in `markdown/html.lua` and a `NOTICE` entry);
   `doc/testing.md` section 2 notes the `--unsafe` flag for `html-*`;
   `doc/plan.md` row 0013 set to `in progress` (to `done` once tasks 9-10
   pass on the host); this file's Status likewise.
- [x] 9. (host verify: oracle and pair baseline) Needs `cmark` (and
   `cmark-gfm` if other inputs need it; `port install cmark cmark-gfm`):
   `sh tools/oracle/commonmark-own` generates `html-*.expected`/`.meta`;
   confirm the diff shows no change to existing `.expected` files (the
   `--unsafe` flag is limited to `html-*`); commit them. Then
   `make test-pairs`, triage failures (parser fix or `skip.lua` with reason,
   never hidden), raise `threshold.lua` `own` to the achieved pass count,
   record the html counts in `doc/references.md` (Pair baseline). (verified on host 2026-11-15)
- [x] 10. Final gates. In the sandbox: `agent-test --full` must pass and
   `make size banned` clean (the 400-line gate matters for `block.lua`,
   `container.lua`, `inline.lua`, `html.lua`, `render.lua`). (host verify:
   `make ci` for stylua and luacheck, `make format-check lint`, which are
   not installed in the sandbox). Order host-only work as 9 then 10 in one
   round-trip; then set `doc/plan.md` and this file's Status to `done`. (verified on host 2026-11-15)

Notes (task 7): 82 `html-*.in` written and all hand-verified through the
projection, no parser bug found. `tools/oracle/commonmark-own` passes
`--unsafe` for `html-*`. `skip.lua` is empty and consistent. Host: run task 9;
an `html-*` that fails there is a parser bug or a cmark-version difference
(comment grammar differs between cmark 0.29 and 0.31, so no input depends on
`--` inside a comment).

Notes (task 10): sandbox gates in the final report; host: `make ci`,
`make format-check lint`.

## Done when

All seven HTML block conditions and inline raw HTML (tags, comments,
processing instructions, declarations, CDATA) are in the model and render
verbatim with `DocPreviewHtml`, also inside block quotes and list items,
wrapped to the width and mapping 1:1 to source lines; no HTML is interpreted;
own pair inputs, goldens and integration specs pass; `agent-test --full`
passes and the quality gates are clean.
