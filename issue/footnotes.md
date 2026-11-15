# 0016 Footnotes

Status: done

Goal: `[^label]` references and `[^label]: text` definitions render as
numbered markers plus a footnote section at the end of the document.

Touches: `markdown/block.lua` (definitions, multi-line bodies as blocks),
`markdown/inline.lua` (`footnote_ref`), `document/model.lua`
(`footnote_def`, `footnote_ref`), `document/render.lua` (section, numbering
in order of first use, map to the first-use source line), `core/out.lua`
if needed, `core/highlight.lua`.

Brings: GFM-style footnotes (an extension beyond CommonMark and the GFM
spec). Roadmap lines "footnote-style `[n]` links" and "footnotes" are
different features; the numbering decision (separate sequences) is taken in
0007 so this slice does not renumber links.

Tests: unit; golden; pairs in an extension manifest: no CommonMark/GFM
expectation exists, so expected HTML comes from `markdown-it-footnote`
(MIT, verify) only as an own-input oracle run, or the pairs are omitted
with a recorded reason; decide in this slice and record in
`doc/references.md`.

References: `markdown-it-footnote` (MIT, verify licence before use);
`doc/architecture.md` 4.3, 6.1, 10 (open item 7: GFM alerts stay out);
`doc/document-model.md` (`footnote_def`, `footnote_ref`).

Depends on: 0007 (numbering decision, Links section), 0010, 0011 (bodies
are blocks).

Out of scope: GFM alerts, inline footnotes, footnote back-references.

## Decisions for the plan

- Size gates: `block.lua` 316, `render.lua` 309, `inline.lua` 366,
  `container.lua` 273 (limit 400). All footnote code goes in new modules:
  `markdown/footnote.lua` (definition detection and body collection),
  `document/footnotes.lua` (numbering registry, like `linklist.lua`),
  `document/footnote_render.lua` (marker text and section; pattern of
  `table_render.lua`). Existing files only gain short hook calls.
- Model: block `footnote_def{label, children, src_start, src_end}`, inline
  `footnote_ref{label}` (no range). Registered in `model.kinds` /
  `inline_kinds`; `validate` checks `label` is a non-empty string and that
  `footnote_def` has `children`.
- Numbering: separate sequence from links (decided in 0007), `ctx.footnotes`
  registry created in `render.M.render` next to `ctx.links`; number by first
  use in document order, duplicates share a number. Markers render as `[^n]`
  (group `DocPreviewFootnoteRef`, `link = "Special"`, `default = true`).
  Definitions are not rendered in place; a definition that is never
  referenced is not rendered; a reference without a definition stays literal
  text (parser decision: `footnote_ref` only for defined labels).
- Section: "Footnotes" title (`DocPreviewH2`, as the Links title) then one
  entry per used footnote, `n. ` prefix plus the body blocks rendered with
  the normal block renderer (hanging indent like list items), appended after
  the document body and before the Links section (Links stay last; links
  inside footnote bodies are numbered after those in the body). Section
  entries map to their definition's source range; markers map through their
  paragraph. Spec says "map to the first-use source line": confirm in task 1
  which one the section entry takes (default: the definition range, since
  that is the text shown) and record it in `doc/architecture.md` 4.1.
- Parsing: `[^label]:` at the start of a line (indent 0-3) starts a
  definition; it must be recognised before `link_syntax.extract`, otherwise
  `[^x]: text` is consumed as a link reference definition with label `^x`.
  Body: the rest of the first line plus following lines indented by 4
  columns (container-style strip), blank lines inside the body allowed when
  the next non-blank line is still indented, lazy paragraph continuation
  like list items. Body is parsed with the recursive `scan`/`build` so it
  holds blocks (paragraphs, lists, code). Label normalisation reuses
  `link_syntax.normalize`; labels with whitespace are not footnote labels.
  Labels are collected in pass 1b into a footnote set shared via `refs`
  (reserved key shape decided in task 3) so inline parsing knows which
  `[^x]` to turn into a `footnote_ref`.
- Inline: in `inline.lua` the `]` handler asks a tiny function from
  `markdown/footnote.lua` before link resolution: opener text `^label`
  with a defined label gives `footnote_ref`, and it must win over reference
  link lookup. No change to the bracket stack otherwise.
- Pair projection and oracle: `cmark-gfm --extension footnotes` is the
  oracle (not in the sandbox, host verify), not `markdown-it-footnote`, so
  the open question in the outline is settled: pairs are kept, recorded in
  `doc/references.md`. `tools/oracle/commonmark-own` gets a
  `gfm-footnote-*` case before `gfm-*` (adds `--extension footnotes`, keeps
  strikethrough, tasklist, so existing `.expected` stay byte-identical).
  `project_html.lua` emits the cmark-gfm footnote form (`sup` reference,
  `section.footnotes` list with numbered `li`, back-reference anchor at the
  end of the last paragraph; exact markup unconfirmed until host).
- Out of scope: GFM alerts, inline footnotes `^[text]`, back-references in
  the rendered preview (only emitted by the HTML projection to match the
  oracle), footnote definitions inside lists/quotes beyond what the
  recursive scan gives for free (tested, deviation recorded if the oracle
  disagrees).

## Tasks

- [x] 1. Model (done; section map rule confirmed: definition range, recorded in architecture 4.1), registry, highlight (+ unit tests). `document/model.lua`:
   `M.footnote_def`, `M.footnote_ref`, kinds, `validate` cases (empty label,
   missing children, inline ref without range is valid). New
   `document/footnotes.lua`: `new()`, `number(reg, label, line)` (first use,
   duplicates share), `section`-independent (rendering is task 2).
   `core/highlight.lua`: `DocPreviewFootnoteRef` (+ `DocPreviewFootnote`
   if the section needs a label group); extend
   `tests/unit/highlight_spec.lua`. Unit tests: new
   `tests/unit/footnotes_spec.lua` (numbering order, duplicates, separate
   from links) and validate cases in `tests/unit/document_spec.lua`.
- [x] 2. Renderer (+ unit tests). New `document/footnote_render.lua`
   (marker `[^n]` with group, section with hanging-indent entries, wrap at
   `ctx.width`, map entries ascending and covering every row). `render.lua`:
   `footnote_ref` in `flatten`, `footnote_def` handler that renders nothing,
   `ctx.footnotes` setup and section call in `M.render` before the Links
   section; only short hooks, file stays under 400. Definitions are looked
   up by label (a pre-pass over `doc.children` collecting `footnote_def`
   nodes, including nested ones). Unit tests in `tests/unit/document_spec.lua`
   on hand-built trees: single ref, two refs in order of first use, repeated
   ref shares number, unused def not shown, ref without def (literal),
   multi-paragraph body, body with a list and a code block, ref inside a
   heading and a table cell, numbers separate from links with both present
   (`render_links_spec.lua`), width sweep (no row wider than `ctx.width`),
   wide characters, ref in a footnote body, map entries.
- [x] 3. Block parsing of definitions (done; a definition interrupts a paragraph, per cmark-gfm, pinned in test; footnote set lives in `refs[" footnotes"]`) (+ unit tests). New
   `markdown/footnote.lua`: `start(line)` returning label and rest of the
   first line, body-line continuation test (4-column indent, blank-line
   rule). `block.lua` `scan`: hook before paragraph/definition handling,
   emit pending `{ footnote = true, label, children, start, last }` with
   the body scanned recursively (ranges via `linenos`); `build` emits
   `model.footnote_def`; `collect_definitions` recurses into footnote
   children, skips them for `link_syntax.extract`, and records the labels
   in the shared footnote set; `take_task_box`/`is_tight` unaffected. Fix
   `container.lua` only where a test shows a break. Tests in new
   `tests/unit/markdown_footnote_spec.lua`: one-line def, multi-line
   paragraph body, indented continuation paragraph after a blank line,
   lazy continuation, body with list and fenced code, def ends at an
   unindented line, def after and before its reference, adjacent defs,
   duplicate label (first wins), label normalisation (case), invalid
   labels (empty, whitespace), `[^x]: url` is not a link definition,
   def interrupting a paragraph (decide by oracle, test the chosen rule
   and note it), ranges at line > 1, def in a quote and list item.
   `block.lua` stays under 400 lines.
- [x] 4. Inline references (done; hook calls `footnote.ref_label`; footnote set is `refs[" footnotes"]`, first-definition-wins is trivially consistent since the set only records existence) (+ unit tests). `inline.lua`: `]` handler calls
   the `markdown/footnote.lua` helper first; `[^label]` with a defined
   label gives `model.footnote_ref`, otherwise text/links as before
   (`[^x](url)` and `[^x][r]` keep link behaviour only when the label is
   undefined). Make the footnote set reachable from `inline.parse(text,
   refs)` without changing its signature. Tests in
   `tests/unit/markdown_inline_spec.lua` (or a new
   `markdown_footnote_inline_spec.lua`): ref in text, between emphasis,
   inside link text (not a ref: links do not nest, decide and pin),
   undefined label stays literal, `\[^x]` escaped, in a code span, two refs
   to one label, adjacent `[^a][^b]`, label with punctuation, uppercase
   vs lowercase definition, image alt. `inline.lua` stays under 400 lines
   (366 now: keep the hook to a few lines, move any helper out).
- [x] 5. Pair projection (done; markup unconfirmed until task 8) (+ unit tests). `tests/pairs/project_html.lua`:
   `footnote_ref` as `<sup class="footnote-ref">` with the number taken in
   order of first use, `footnote_def` collected into the trailing
   `<section class="footnotes">` list (unused defs omitted), back-reference
   appended to the last paragraph of each entry; extend
   `tests/unit/pairs_project_spec.lua` with hand-built cases (single,
   repeated ref, unused def, multi-paragraph body, ref in a table cell).
   Exact whitespace and attributes follow cmark-gfm and are unconfirmed
   until the host task 8.
- [x] 6. Golden and integration (done; title row maps to the first definition start, entries to the definition range). Golden fixtures
   `tests/golden/markdown/footnotes-*.in|.out|.spans` at width 40
   (`UPDATE_GOLDEN=1 make test-golden`, review by hand): `footnotes-basic`
   (two refs, repeated ref, section), `footnotes-body` (multi-paragraph,
   list, code, wrapped long entry), `footnotes-links` (links and footnotes
   together: separate sequences, Links last), `footnotes-undefined` (ref
   without def, unused def). Assert no line wider than 40 and
   `DocPreviewFootnoteRef` spans present. New
   `tests/integration/footnotes_spec.lua` (pattern of `images_spec.lua`):
   buffer renders, extmarks present, scroll/cursor mapping from the
   reference line and from the definition line land on their rows and
   back, including a wrapped entry. Existing golden and scroll specs keep
   passing.
- [x] 7. Docs (done). `doc/document-model.md` (`footnote_def`/`footnote_ref` rows:
   fields, definition rule, unreferenced and undefined behaviour,
   rendering, groups); `doc/architecture.md` 4.1 (map of section entries),
   4.3 (marker `[^n]`, section placement before Links, separate
   sequences), 6.1 (definition syntax, body indent, lazy rule, label
   rules), 7 (`DocPreviewFootnoteRef`); `doc/references.md` (GFM footnotes
   behaviour notes, oracle `cmark-gfm --extension footnotes`, answer to the
   pairs question, no code ported, `markdown-it-footnote` not used);
   `doc/testing.md` section 2 (`--extension footnotes` for
   `gfm-footnote-*`); `doc/plan.md` row 0016 `in progress` when work
   starts and updated at the end (to `done` once task 8 passes on the
   host); this file's Status likewise.
- [x] 8. (inputs and oracle case done: 21 `gfm-footnote-*.in` hand-checked through the projection, no parser bug found; `tools/oracle/commonmark-own` has the case. Host steps: with `cmark-gfm` (footnotes extension) run `sh tools/oracle/commonmark-own`; `git diff` must show no change to existing `.expected`; compare new `.expected` with the projection and confirm the footnote HTML form (`sup.footnote-ref`, `section.footnotes` `ol`, `li id=fn-*`, backref anchors, `-2` ids for repeats, last block not a paragraph (`body-list-code`), label case in ids (`uppercase-label`)) and the rule that a definition interrupts a paragraph (`interrupts-paragraph`), plus defs in quote/list (`in-quote`, `in-list`); adjust `project_html.lua`; `make test-pairs`; triage failures (parser fix or `skip.lua` with reason); raise `threshold.lua` `own`; record counts in `doc/references.md` Pair baseline) Own inputs
   `tests/pairs/markdown/own/gfm-footnote-*.in` (about 20, fresh text):
   single, multiple in order, reference order differs from definition
   order, repeated ref, unused def, undefined ref, multi-line body,
   continuation paragraph, body with list and code, lazy continuation, def
   before use, def in quote and list item, uppercase label, escaped ref,
   ref in code span, ref in table cell, `[^x]: url` not a link def. Hand-
   check each through the projection first. `tools/oracle/commonmark-own`:
   add `gfm-footnote-*` before `gfm-*` with `--extension footnotes` (plus
   strikethrough, tasklist), update its header comment. Host needs
   `cmark-gfm` with the footnotes extension: `sh tools/oracle/commonmark-own`,
   check `git diff` shows no change to existing `.expected`, confirm the
   projection markup of task 5 (adjust `project_html.lua`), `make
   test-pairs`, triage failures (parser fix or `skip.lua` with reason,
   never hidden), raise `threshold.lua` `own` to the achieved count,
   record counts in `doc/references.md` (Pair baseline). (verified on host 2026-11-15)
- [x] 9. Final gates (sandbox done: `agent-test --full` passes, `make size banned` clean; host: `make ci`, `make format-check lint` for stylua/luacheck). Sandbox: `agent-test --full` passes and
   `make size banned` clean (400-line gate: `block.lua`, `render.lua`,
   `inline.lua`, new modules). (host verify: `make ci` for stylua and
   luacheck, `make format-check lint`, not installed in the sandbox). Do
   8 then 9 in one host round-trip, then set `doc/plan.md` and this
   file's Status to `done`. (verified on host 2026-11-15)

## Done when

Footnote references and definitions parse, render as `[^n]` markers (numbered
by first use, separate from links) plus a Footnotes section with block
bodies, map to source lines, and fit `ctx.width`; golden, integration, unit
and own pair tests pass; `agent-test --full` passes and the quality gates are
clean.
