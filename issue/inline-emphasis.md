# 0006 Inline emphasis, strong, code span

Status: done

Goal: `*em*`, `**strong**`, `~~strike~~` and `` `code` `` in paragraphs and
headings render as styled text with the markers removed, plus hard breaks,
soft breaks, backslash escapes and entity references.

Brings: `markdown/inline.lua` (code spans, escapes, entities, breaks,
delimiter-stack emphasis/strong/strike), `markdown/entities.lua`, inline
kinds in the model, a flattening renderer that keeps style ranges, a wrap
that maps those ranges onto wrapped lines (`core/text.wrap_styled`),
inline highlight groups, own-input pairs, golden `.spans`.

Touches: `lua/doc_preview/{markdown/inline,markdown/entities,markdown/block,document/model,document/render,core/text,core/highlight}.lua`,
`tests/{unit,golden,integration,pairs}/`, `tools/oracle/commonmark-own`,
`doc/{references,plan}.md`, `NOTICE`.

Depends on: 0004 (span application, `.spans` golden, pair runner), 0005
(gates).

References (recorded in `doc/references.md`): CommonMark spec sections
"Emphasis and strong emphasis", "Code spans", "Backslash escapes", "Entity
and numeric character references", "Hard line breaks", "Soft line breaks";
GFM "Strikethrough (extension)": behaviour only, no spec text or examples
copied (CC BY-SA). Pair inputs are written here; expectations come from
`cmark` / `cmark-gfm`. `doc/architecture.md` 4.3, 6.1, 7;
`doc/document-model.md`.

Decisions taken for this slice:

* No code is ported (algorithm studied in commonmark.js / markdown-it);
  recorded in `doc/references.md`.
* Inline nodes carry no `src_start`/`src_end` (as `text` already did);
  `model.inline_kinds` lists them and `validate` exempts them.
* The block pass keeps trailing blanks of paragraph lines (two of them
  before a newline are a hard break); the inline pass strips leading blanks
  of continuation lines and trailing blanks at the end of the block.
* In the flattened text a hard break is `"\n"` and a soft break a space;
  `wrap_styled` treats `"\n"` as a forced line end, `wrap` still collapses
  all whitespace. Spaces inside code spans collapse when wrapped.
* Tilde runs: only runs of 1 or 2 delimit strikethrough, opener and closer
  must have equal length (cmark-gfm behaviour to be confirmed in task 10).
* Limits: ASCII punctuation/whitespace classes (plus U+00A0) for flanking;
  a small named-entity table, unknown names stay literal.
* Span columns follow 0004: 0-based bytes, end exclusive. Nested styles
  produce overlapping spans; golden `.spans` sorts ties by end column and
  group so output is deterministic.
* Inline groups: `DocPreviewEmph` (italic), `DocPreviewStrong` (bold),
  `DocPreviewStrike` (strikethrough), `DocPreviewCode` (link `String`), all
  `default = true`.

## Tasks

- [x] 1. Model: `document/model.lua` gains `emph`, `strong`, `strike`
   (`inlines`), `code` (`value`), `softbreak`, `hardbreak` constructors,
   registers the kinds (`inline_kinds`) and `validate` accepts them without
   a source range. Unit tests in `tests/unit/document_spec.lua`.
- [x] 2. Styled wrap: `core/text.lua` shares one greedy `layout` (segments
   with byte offsets) between `wrap` (unchanged behaviour) and the new
   `wrap_styled(s, width, ranges)` (forced breaks at `"\n"`, ranges mapped
   to per-line spans). Unit tests in `tests/unit/text_spec.lua`: equals
   `wrap` without ranges, range on one line, range across a wrap, collapsed
   spaces and multibyte byte columns, hard-split words, hard break offset,
   never exceeds the width.
- [x] 3. Renderer and highlight groups: `document/render.lua` flattens the
   inline tree to text plus ranges (groups `DocPreviewEmph/Strong/Strike/Code`)
   and uses `wrap_styled` for paragraph and heading; `core/highlight.lua`
   defines the groups. Unit tests: markers removed, spans, nesting, wrapped
   styled text within the width, breaks, heading plus inline spans;
   `highlight_spec` for the groups.
- [x] 4. `markdown/inline.lua`, part 1: code spans (equal-length backtick
   runs, newline to space, one-space strip, unclosed run literal),
   backslash escapes (ASCII punctuation only, backslash-newline is a hard
   break), entities (`markdown/entities.lua`, decimal and hex, invalid and
   unknown literal, result never re-parsed as markup), hard and soft breaks
   (two trailing spaces; leading blanks of continuation lines dropped),
   trailing blanks stripped. Unit tests `tests/unit/markdown_inline_spec.lua`.
- [x] 5. `markdown/inline.lua`, part 2: delimiter stack for `*` and `_`
   (left/right flanking, `_` intraword rule, multiple-of-three rule,
   leftover delimiters as text, strong from 2+2, nesting). Unit tests in the
   same spec.
- [x] 6. Strikethrough (`~` runs of 1 or 2, equal length, flanking as `*`) in
   the same stack. Unit tests in the same spec.
- [x] 7. Wire into the block pass: `markdown/block.lua` calls `inline.parse`
   for paragraph, ATX and setext content (keeps trailing blanks of lines);
   `tests/pairs/project_html.lua` projects `em`, `strong`, `del`, `code`,
   `br` and soft breaks, and drops its blank-stripping hack. Existing
   block and projection specs updated, new cases added.
- [x] 8. Golden and integration: fixtures `inline-emphasis`,
   `inline-code-strike`, `inline-breaks-escapes`, `inline-wrap` (+ `.width`)
   with `.spans`; golden span sort made deterministic;
   `tests/integration/inline_spec.lua` (preview text and extmarks).
- [x] 9. Own pair inputs and oracle: 49 inputs (emphasis, strong, code
   spans, escapes, entities, breaks, `gfm-` strikethrough);
   `tools/oracle/commonmark-own` uses `cmark-gfm --extension strikethrough`
   for `gfm-*.in` and records tool and command in `.meta`; `skip.lua`
   entries `inline: 0006`/`escapes: 0006` removed (those pairs become
   pending until `.expected` exist). `doc/references.md`, `NOTICE`
   updated. No `.expected` files: no `cmark` in the sandbox. The projected
   HTML of every new input was checked by hand against CommonMark behaviour.
   Host check: `tools/oracle/commonmark-own` (needs `cmark` and `cmark-gfm`). (verified on host 2026-11-15)
- [x] 10. Pair baseline (host): run `tools/oracle/commonmark-own`, commit the
   `.expected`/`.meta` files, run `make test-pairs`, triage failures (fix the
   parser or add a `skip.lua` entry with a reason; the `gfm-strike-mismatch`
   and `emph-run-lengths` inputs are the likeliest divergences), raise
   `threshold.lua`, record counts and tool versions in `doc/references.md`,
   run `make test` and `make ci`, then mark tasks 9 and 10 `[x]`. (verified on host 2026-11-15: commonmark-own 548/548, threshold 548, baseline in `doc/references.md`)

## Done when

`:DocPreview open` on a Markdown file shows emphasis, strong, strike and
code spans styled (extmarks) with markers removed, hard and soft breaks,
escapes and entities resolved, wrapped within the width; `make ci` passes;
the pair suite reports the new cases (pending until the oracle ran).

## Out of scope

Links, images, raw HTML (0007, 0013, 0015); Unicode punctuation classes and
the full HTML5 entity table; rst inline markup.
