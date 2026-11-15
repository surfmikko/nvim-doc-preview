# 0011 Lists

Status: done

Goal: bullet, ordered, nested and task lists render with markers and
hanging indents.

Touches: `markdown/block.lua` (list items on the 0010 container machinery),
`document/model.lua` (`list{ordered,start}`, `list_item{checked}`),
`document/render.lua` (markers, numbering from `start`, nested indent,
`[ ]`/`[x]`), `core/text.lua` (hanging-indent wrap), `core/highlight.lua`
(marker group), `tests/pairs/project_html.lua` (`ul`, `ol`, `li`, task
checkbox projection per cmark `--extension tasklist` if used).

Brings: list item start rules (marker, width, indent), tight versus loose
lists, list ending rules, ordered-list start numbers, nested lists, GFM
task items; hanging indent in `core/text`.

Tests: unit (`start`, `ordered`, tight/loose, nesting, source ranges,
`core/text` hanging indent); own-input pairs for "List items", "Lists",
GFM "Task list items (extension)" (cmark oracle with the extension
recorded in `.meta`); golden with nested and task lists; no line exceeds
width.

References: CommonMark "List items", "Lists"; GFM "Task list items
(extension)" (behaviour only). Port: `markdown-it` (MIT) `list.js` or
`commonmark.js` (BSD-2). `doc/architecture.md` 4.3 (hanging indents), 6.1;
`doc/document-model.md` (`list`, `list_item`).

Depends on: 0010 (container machinery), 0009 (`* * *`), 0006 (item
inlines). Links in items are not required.

Out of scope: fenced code and tables inside items (0012, 0014 add their
own container cases), definition lists, RST lists.

## Decisions for the plan

- The model gets one field beyond the outline: `list.tight` (bool). The
  renderer needs it for blank lines between items and the `hr`/`p`
  projection needs it for `<li>` without `<p>`. `doc/document-model.md`
  gains the field (task 7).
- Hanging indent is done by the renderer: item children render with
  `ctx.width` minus the marker width, then the first line gets the marker
  and the rest a blank indent of the same width (same shape as the quote
  prefix). `core/text.wrap` is expected to stay unchanged; if the coder
  finds it needs a hanging-indent argument after all, add it with unit
  tests in the same task and say so in the task note.
- `markdown/block.lua` is 237 lines; the list code goes into a new
  `markdown/container.lua` that also takes over `quote_marker`/`take_quote`
  so quotes and lists share one continuation routine (400-line gate).
- GFM task items: the oracle is `cmark-gfm --extension tasklist` (plus the
  already used `strikethrough`); recorded in `.meta`.

## Tasks

- [x] 1. Model, renderer, highlight (+ unit tests). `document/model.lua`:
   `M.list(ordered, start, tight, items, src_start, src_end)` and
   `M.list_item(checked, children, src_start, src_end)` (`checked` is
   `nil`/`true`/`false`), kinds registered, `validate` recurses into items
   and their children. `document/render.lua`: `list` and `list_item`
   handlers. Marker `• ` for bullets (nested bullets may alternate glyph;
   keep one local constant table, comment pointing to 0018 for the ascii
   charset), `N. ` for ordered numbered from `start`, marker column width
   padded to the widest number in the list so item text lines up. Task
   items use `[ ] ` / `[x] ` as the marker text in place of the bullet
   (ordered task items keep the number, then the box). Item children render
   through the shared `render_blocks` with `ctx.width` reduced by the
   marker width (min 1); first line gets the marker, other lines a blank
   indent of the same width, blank separator lines inside an item stay
   empty (no trailing blanks needed). Between items: no blank line when
   `tight`, one blank line when loose; inside a tight item the children
   are not separated by blank lines when they are paragraph then a nested
   list. One map entry per child shifted unchanged; an empty item maps to
   its own source line and renders the marker alone. `core/highlight.lua`
   defines `DocPreviewListMarker` (link to `Special`, `default = true`),
   covered in `tests/unit/highlight_spec.lua`; the marker gets that span.
   Unit tests in `tests/unit/document_spec.lua` on hand-built trees:
   bullet, ordered from 1 and from 7, number width alignment (`9.` to
   `10.`), wrapped item (hanging indent, no line wider than width),
   tight vs loose, nested list indent, task `[ ]`/`[x]`, empty item, item
   with two paragraphs, list inside a blockquote, tiny width, marker
   span, map entries. Existing specs keep passing.
- [x] 2. Container refactor and single-level lists in the parser. Create
   `markdown/container.lua` holding `quote_marker`/`take_quote` moved out
   of `block.lua` (behaviour unchanged, all block-quote specs still pass)
   plus the list item machinery; `block.lua` keeps `scan` and the leaf
   rules and requires it (avoid a require cycle: pass `scan` in, as
   `take_quote` already reaches it, or inject it once). Add a `list`
   pending entry (`ordered`, `start`, `delim`, items each holding nested
   `pending` children and their own `start`/`last` source lines);
   `collect_definitions` and `build` recurse into items (shared `refs`),
   `build` emits `model.list`/`model.list_item` with `tight = true` as a
   placeholder until task 3. List item start: 0-3 columns of indent, a
   bullet (`-`, `+`, `*`) or 1-9 digits plus `.` or `)`, then 1-4 spaces
   (content column = marker width + spaces) or a tab, or end of line
   (content column = marker width + 1); 5+ spaces after the marker means
   content starts with indented code, so content column = marker + 1.
   Item continuation: a following line indented at least the content
   column belongs to the item (strip that many columns with
   `expand_indent` tab handling); a non-blank line indented less ends the
   item unless it is a lazy paragraph continuation (reuse the quote lazy
   rule: only when the item's last inner block is an open paragraph and the
   line does not start a block); a blank line followed by an indented line
   continues the item; two blank lines are not special in CommonMark. An
   item that starts with a blank line followed by a blank line is empty
   and ends there. Same marker kind continues the list: same bullet char,
   or same ordered delimiter; a different bullet char or delimiter starts a
   new list. An ordered list may interrupt a paragraph only if it starts
   at 1; an empty item cannot interrupt a paragraph; a bullet may. Order
   of tests per line: blank, ATX, setext underline, thematic (so `* * *`
   and `- - -` stay rules, 0009 precedence), quote start, then list item
   start. Quote and list inside each other must not crash (full nesting
   is task 3). Update the file header comment. Unit tests in
   `tests/unit/markdown_block_spec.lua`: bullets with each marker, ordered
   with `.` and `)`, start numbers (`0.`, `3.`, ten digits is not a
   marker), indent 0-3 vs 4, marker without space is text, 1-4 spaces vs 5,
   empty item, marker change starts a new list, delimiter change starts a
   new list, ordered interrupt rule (`2.` does not interrupt, `1.` does),
   empty item cannot interrupt, lazy continuation line, continuation by
   indent, blank line then indented line stays in the item, less-indented
   line ends it, `* * *` and `- - -` are rules, `-` after paragraph is
   still a setext underline, source ranges of list, item and children
   (lists starting at line > 1), definition inside an item used outside.
   Existing specs keep passing and `block.lua` plus `container.lua` each
   stay under 400 lines.
- [x] 3. Tight/loose, nesting, task items, ending rules (parser + unit
   tests). Nested lists: an item whose content column indent starts
   another list item produces a nested `list` through the same recursive
   `scan` (no special case); lists inside quotes and quotes inside items
   (`> - a`, `- > a`) work through the shared machinery; `1. - a`
   style same-line nesting. Tight/loose: a list is loose if any two
   directly adjacent items, or two direct children of one item, are
   separated by a blank line (blank lines inside a nested list or fenced
   block only affect that inner list; a trailing blank line at the end of
   the last item does not make the list loose), else tight; set
   `list.tight` for real. List ending: a non-blank, less-indented
   non-lazy line that is not an item of the same list ends it; two lists
   separated only by blank lines with different markers are two lists; a
   blank line then an unindented paragraph ends the list. Task items:
   first inline content `[ ]`, `[x]` or `[X]` followed by a space or end
   of paragraph at the start of the item's first paragraph sets
   `checked` and strips the box from the text (only in a list item's first
   paragraph; `[ ]` with no following text still counts per GFM, check the
   oracle in task 5; `[]`, `[xx]`, `[ x]` and a box not at the start are
   plain text). Unit tests in `tests/unit/markdown_block_spec.lua`:
   nested bullet in bullet, ordered in bullet, three levels, nested with
   less-than-content-column indent (not nested), sibling after nested,
   dedent two levels, tight, loose by blank between items, loose by
   blank between item children, nested blank does not loosen the outer
   list, trailing blank does not loosen, list ending by paragraph, two
   lists by marker change, list in quote, quote in list, task items
   (`[ ]`, `[x]`, `[X]`, not a task: `[]`, `[xx]`, `[ x]`, mid-text),
   source ranges at every level, no crash on a fence (`- ```) and a table
   row inside an item (paragraph fallback until 0012/0014).
- [x] 4. End to end wiring, golden and integration (+ `core/text` decision).
   Confirm `session`/`init` need no change. Golden fixtures
   `tests/golden/markdown/lists-*.in|.out|.spans` at width 40 (generate
   with `UPDATE_GOLDEN=1 make test-golden`, review by hand): `lists-bullet`
   (three markers, wrapped long item, tight and loose), `lists-ordered`
   (start 1, start 7, `9.` to `10.` alignment, `)` delimiter),
   `lists-nested` (three levels, ordered inside bullet, quote inside item,
   list inside quote), `lists-task` (checked, unchecked, nested task,
   inline emphasis and a link inside an item, link marker numbering
   unchanged). Check no line is wider than 40 and the marker span is on
   every item's first line. Add `tests/integration/lists_spec.lua`
   (pattern of `blockquote_spec.lua`): a buffer with nested and task lists
   renders in the preview window, no rendered line exceeds the window
   width, and cursor/scroll mapping from a source line inside a nested item
   (including a lazy continuation line) lands on the matching preview line
   and back. If the hanging-indent decision in this file turned out
   wrong, add the `core/text` change and its `tests/unit/text_spec.lua`
   cases here. Existing scroll specs keep passing.
- [x] 5. Pair projection and own inputs (host verify: the oracle).
   `tests/pairs/project_html.lua` projects `list` to `<ul>`/`<ol>` (with
   `start="N"` only when `start ~= 1`), `list_item` to `<li>`, cmark's
   layout (`<li>` content inline for a tight single paragraph, `<li>\n`
   then blocks then `</li>` otherwise); in a tight list the item's direct
   paragraphs lose their `<p>` wrapper, loose lists keep it; empty item is
   `<li></li>`; task items follow `cmark-gfm --extension tasklist`
   (`<input type="checkbox" disabled="" />` inside the item, `checked=""`
   when checked; record the exact form seen from the oracle in the unit
   spec). Extend `tests/unit/pairs_project_spec.lua` with hand-built and
   parsed cases. Extend `tools/oracle/commonmark-own` to pass
   `--extension tasklist` (alongside `strikethrough`) so `.meta` records
   it, without changing results for existing inputs (the new extension
   does not alter existing outputs; verify by diff on the host). Write
   about 40 fresh inputs `tests/pairs/markdown/own/list-*.in` (no spec
   text): each bullet marker, ordered `.`/`)`, start 0/1/7, marker
   change, delimiter change, tight, loose, loose by nested content,
   nested 2-3 levels, content column 2-4 spaces, 5 spaces (skip: indented
   code), indent 1-3 vs 4, empty items, empty item cannot interrupt,
   ordered interrupt rule, lazy continuation, blank then indented
   continuation, list ending by paragraph, list in quote, quote in list,
   `* * *` inside and between lists, `-` setext vs list, `1.` without
   space, long digits, task items (`[ ]`, `[x]`, `[X]`, not tasks,
   nested, in ordered), plus entries for "Precedence". Cases needing
   fenced or indented code in an item go to `skip.lua` with reasons
   (`fenced code: 0012`, `indented code: later slice`). Replace the stale
   `own/quote-list-inside` and `own/quote-list-mix` entries in `skip.lua`
   only if the cases now parse as expected (a stale skip fails the run).
   Check every input by hand against the expected HTML through the
   projection. Without `.expected` the runner reports them pending.
   (host verify: `port install cmark-gfm`; `sh tools/oracle/commonmark-own`
   generates `list-*.expected`/`.meta`; commit them.)
   Note: projection, unit spec, own inputs (71: `list-*`, `gfm-list-task-*`; task cases are `gfm-` so the oracle uses cmark-gfm), `commonmark-own` tasklist extension and skip entries are done; every input was projected by hand and checked against CommonMark. `quote-list-inside`/`quote-list-mix` skips removed (they pass by hand). Skipped: `list-fence-inside` (0012), `list-indented-code-5-spaces`, `list-indented-code-inside`. The tasklist HTML form (`<input type="checkbox" [checked="" ]disabled="" /> ` glued after `<li>`, also in loose items) is from memory of cmark-gfm. Host: `port install cmark cmark-gfm`; `sh tools/oracle/commonmark-own`; check existing `.expected` are unchanged by the diff; commit `list-*.expected/.meta`; compare the loose task item and `[ ]`-only forms and fix `project_html.lua` if they differ. (verified on host 2026-11-15)
- [x] 6. Pair baseline (host verify: needs `cmark-gfm` and the task 5
   expectations): `make test-pairs`; triage every failure (fix the parser
   or add a `skip.lua` entry with a reason; deviations are reviewed, not
   hidden), settle the task-item cases noted in task 3 against the
   oracle, raise `threshold.lua` `own` to the achieved pass count, record
   the list counts in `doc/references.md` if it keeps per-section counts.
   Host only: after task 5 expectations exist run `make test-pairs`, triage failures (parser fix or `skip.lua` with reason), settle the task-item cases (`[ ]` without text, loose) against cmark-gfm, raise `threshold.lua` `own` to the pass count, record counts in `doc/references.md` (Pair baseline). (verified on host 2026-11-15)
- [x] 7. Docs and wrap-up. `doc/plan.md` row 0011 set to the real status
   (`in progress` until tasks 5-6 pass on the host, then `done`);
   `doc/document-model.md` `list`/`list_item` rows gain `tight` and the
   rendering note (marker glyphs until 0018, numbering from `start`,
   alignment, hanging indent via reduced `ctx.width`, task `checked`);
   `doc/architecture.md` 4.2/6.1 get the list item continuation and
   tight/loose summary if not implied; `doc/references.md` gets the
   CommonMark "List items", "Lists" and GFM "Task list items" behaviour
   notes (behaviour only; if code was ported from `markdown-it` or
   `commonmark.js`, add a header comment in the ported file and a
   `NOTICE` entry, otherwise state none was); set this file's Status to
   `done` once tasks 5-6 are verified.
   Note: no code was ported (stated in `doc/references.md`); `doc/plan.md` row set to done except host check.
- [x] 8. Final gates: run `agent-test --full` (must pass) and the stylua
   and luacheck gates where runnable (`make format-check lint size
   banned`; the 400-line size gate matters for `block.lua`,
   `container.lua` and `render.lua`). If stylua or luacheck are missing in
   the sandbox, mark `(host verify: make ci)`. Order host-only work as: 5
   (generate expectations), 6 (baseline), 8 (`make ci`) in one host
   round-trip.
   Note: `agent-test --full` passes; `make size` and banned checks pass; stylua and luacheck are not installed here. Host verify: `make ci`. (verified on host 2026-11-15)

## Done when

Bullet, ordered (with `start`), nested, tight/loose and task lists render
with markers and hanging indents inside `ctx.width`; `* * *` still never
reaches list code; lists work inside block quotes and quotes inside lists;
goldens and integration specs pass; `agent-test --full` passes and the
quality gates are clean.
