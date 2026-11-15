# nvim-doc-preview: references

One entry per external reference: what it is, licence, and how it is used
here. Policy and the porting gate are in `doc/testing.md` 4.2. Credits
for code actually ported also go to `NOTICE`.

Status values: **ported** (code translated to Lua, header comment in the
file, `NOTICE` entry), **dev-only oracle** (run by maintainers to generate
fixtures, nothing shipped), **study-only** (read for behaviour; no text,
code or examples copied).

## CommonMark spec

* URL: https://spec.commonmark.org/
* Version: 0.31.2 (the version whose behaviour was read; verify on update)
* Licence: CC BY-SA 4.0 (text and `spec.json` examples); not MIT-compatible
* Status: **study-only**
* Used for: behaviour of "ATX headings", "Setext headings", "Paragraphs",
  "Tabs" (slice 0004); "Emphasis and strong emphasis", "Code spans",
  "Backslash escapes", "Entity and numeric character references", "Hard
  line breaks", "Soft line breaks" (slice 0006); "Links", "Images",
  "Autolinks", "Link reference definitions" (slice 0007); "Thematic breaks" with
  its interplay with "Setext headings" and "List items" (slice 0009, behaviour
  only, nothing ported); "Block quotes", "Container blocks and leaf blocks",
  "Precedence" (slice 0010: a `>` line starts or continues a quote, up to 3
  columns of indent, one optional space after the marker (a tab counts as
  it); a non-blank line without a marker continues an open quoted paragraph
  lazily unless it would itself start a block; a blank line ends the quote;
  block starts such as ATX, rules and `>` take precedence over paragraph
  continuation; behaviour only, nothing ported from `commonmark.js` or
  `markdown-it`, so no `NOTICE` entry). No spec text or example is committed; pair inputs
  are written in this repo.
  Slice 0015 (rendering only, nothing ported): a paragraph that is exactly one
  image is `<p><img .../></p>`; image plus text, two images or a link around
  an image stay inline in the paragraph; alt is the plain text of the
  description (markup stripped, soft break a space); the `images-block-*`
  own inputs cover these.
* Files: none.

## GFM spec

* URL: https://github.github.com/gfm/
* Licence: CC BY-SA 4.0
* Status: **study-only**. Used for "Strikethrough (extension)" behaviour
  (slice 0006) and "Tables (extension)" (slice 0014: delimiter row rules,
  header/delimiter cell count match, ragged rows, escaped pipes, body ends at
  blank line or other block start); task lists in a later slice. Same rule as the
  CommonMark spec.

## cmark

* URL: https://github.com/commonmark/cmark
* Version: recorded per generated file in `tests/pairs/markdown/own/*.meta`
  (`cmark --version`); baseline version in "Pair baseline" below.
* Licence: BSD-2-Clause (SPDX `BSD-2-Clause`)
* Status: **dev-only oracle**; also studied (`blocks.c`, ATX and setext
  rules). Nothing ported.
* Used for: `tools/oracle/commonmark-own` generates `.expected` (HTML,
  `cmark --to html`) and `.meta` for our own inputs.
* Files: `tools/oracle/commonmark-own`, `tests/pairs/markdown/own/*`.

## Port source for heading rules

Decision for slice 0004: **no code is ported.** The ATX and setext rules
are small and were written from the behaviour read in the spec and
observed in `cmark`, so no header comment or code `NOTICE` entry is
needed. If a later slice ports from `commonmark.js` (BSD-2-Clause) or
`markdown-it` (MIT), it adds its own entry here and in `NOTICE`.

## Lists (slice 0011)

Behaviour notes only, from CommonMark "List items" and "Lists" and GFM
"Task list items (extension)": item start (marker, 1-4 spaces, 5+ means
indented code), continuation by content-column indent, lazy continuation,
tight versus loose, marker/delimiter change starts a new list, ordered
start number, ordered list interrupts a paragraph only at 1, empty item
cannot interrupt. **No code was ported** from `markdown-it` or
`commonmark.js`, so no header comment or `NOTICE` entry. Task items use
`cmark-gfm --extension tasklist` as the oracle. Per-section pair counts
are not recorded yet (task 6 of `issue/lists.md`, host).

## Fenced and indented code (slice 0012)

Behaviour notes only, from CommonMark "Fenced code blocks" and "Indented code
blocks": fence open/close rules (char, length, 0-3 indent, info string,
closer carries no info), indent stripping up to the opener's indent, unclosed
fence runs to the end of the container, info string first word to `lang`,
indented code needs a blank line or block start before it and keeps interior
blanks. **No code was ported** from `markdown-it` or `cmark`, so no header
comment or `NOTICE` entry. Own inputs: `tests/pairs/markdown/own/code-fence-*`,
`code-indented-*`, `code-quote-*`, `code-list-*`, `code-precedence-*`. Pair
counts are not recorded yet (task 9 of `issue/fenced-code.md`, host).

## HTML blocks and raw HTML (slice 0013)

Behaviour notes only, from CommonMark "HTML blocks" and "Raw HTML": seven
block start conditions and their end conditions, condition 7 not interrupting
a paragraph, no lazy continuation, tag/attribute/comment/PI/declaration/CDATA
grammar for inline HTML; and GFM "Disallowed Raw HTML" (tagfilter), which is
not rendered differently here. **No code was ported** from `markdown-it` or
`commonmark.js`, so no header credit or `NOTICE` entry. Own inputs:
`tests/pairs/markdown/own/html-*` (expectations from `cmark --unsafe`).
Pair counts are not recorded yet (task 9 of `issue/html-blocks.md`, host).

## cmark-gfm

* URL: https://github.com/github/cmark-gfm
* Licence: BSD-2-Clause (SPDX `BSD-2-Clause`)
* Status: **dev-only oracle**, nothing ported.
* Used for: expectations of `tests/pairs/markdown/own/gfm-*.in`
  (`cmark-gfm --extension strikethrough --to html`, recorded in each
  `.meta`), generated by `tools/oracle/commonmark-own`; `gfm-table-*` inputs
  add `--extension table`, `gfm-footnote-*` inputs add `--extension footnotes`.

## GFM footnotes (slice 0016)

Behaviour notes only (definition syntax, 4-column body indent, lazy
continuation, a definition interrupting a paragraph, undefined references
staying literal). Oracle: `cmark-gfm --extension footnotes` over
`tests/pairs/markdown/own/gfm-footnote-*` (dev-only). Answer to the pairs
question: pairs are kept; `markdown-it-footnote` is not used and nothing is
ported, so no `NOTICE` entry. The projection's footnote HTML form is
unconfirmed until the host run (`issue/footnotes.md` task 8).

## Port source for inline rules

Decision for slice 0006: **no code is ported.** `markdown/inline.lua` was
written from the spec behaviour; the delimiter-stack idea (opener/closer
matching, the multiple-of-three rule) was studied in `commonmark.js`
(BSD-2-Clause) `inlines.js` and `markdown-it` (MIT) `balance_pairs`, with
no code copied, so no header credit or code `NOTICE` entry is needed.
Known limits: punctuation and whitespace classes are ASCII plus U+00A0
(Unicode punctuation is treated as a letter), and only the named entities in
`markdown/entities.lua` are decoded (unknown names stay literal).

## Port source for tables

Decision for slice 0014: **no code is ported.** `markdown/table.lua` was
written from the GFM "Tables (extension)" behaviour; `markdown-it` (MIT)
`table.js` was only read for the shape of the algorithm, nothing copied, so
no header credit or `NOTICE` entry. The column-width fitting in
`core/table.lua` (proportional shrink, per-column floors, largest-remainder
distribution) and the box drawing in `core/box.lua` are **original**. Own
inputs: `tests/pairs/markdown/own/gfm-table-*` (expectations from
`cmark-gfm --extension table`, host only). Pair counts are not recorded yet
(task 9 of `issue/tables.md`, host).

## Port source for link rules

Decision for slice 0007: **no code is ported.** `markdown/link_syntax.lua`
and the bracket handling in `markdown/inline.lua` were written from the spec
behaviour; the bracket-stack idea (link text processed in its own emphasis
scope, links deactivating earlier `[`) was studied in `commonmark.js`
(BSD-2-Clause) `inlines.js`, no code copied. GFM extended (bare URL)
autolinks are not implemented. Known limits: label matching folds ASCII
case only; definitions are not read from setext heading text; `<...>` that
is not an autolink stays literal (raw inline HTML is 0013).

## mermaid.js (flowchart syntax)

* URL: https://mermaid.js.org/syntax/flowchart.html
* Licence: MIT (mermaid-js/mermaid)
* Status: **study-only**. Node shapes, edge operators (including rank
  length and `o`/`x`/`<` ends), `|text|` and `-- text -->` labels, `&`,
  chains, `<br/>` and markdown strings, ignored styling statements, and the
  rule that a later explicit shape replaces an earlier one. No code copied.
  `tests/pairs/mermaid/own/*.expected` (17 flowchart pairs, plus the class-* ones) are hand-checked facts (see
  `tests/pairs/project_facts.lua`), not oracle output.

## mermaid.js (sequence diagram syntax)

* URL: https://mermaid.js.org/syntax/sequenceDiagram.html
* Licence: MIT (mermaid-js/mermaid)
* Status: **study-only**. Participants/actors with `as`, message operators
  (`->`, `-->`, `->>`, `-->>`, `-x`, `--x`, `-)`, `--)`), `+`/`-` activation
  shorthand, notes, `autonumber`, `loop`/`alt`/`opt`/`par`/`critical`/`break`/
  `rect` blocks. No code copied. Deviation: a message without `:` text is
  accepted (mermaid.js rejects it). `box` is balanced but not modelled;
  `title`, `link(s)`, `properties`, `details`, `destroy` are ignored.
  `tests/pairs/mermaid/sequence/*.expected` (11 pairs) are hand-checked
  facts (`tests/pairs/project_sequence.lua`), not oracle output.

## mermaid.js (class diagram syntax)

* URL: https://mermaid.js.org/syntax/classDiagram.html
* Licence: MIT (mermaid-js/mermaid)
* Status: **study-only**. Class bodies and `Name : member` lines,
  visibility and `$`/`*` suffixes, `<<annotation>>`, `~T~` generics,
  backquoted names, `class Name["label"]`, `namespace`, relation operators
  with cardinalities and `: label`, `note`/`note for`, ignored styling and
  link statements. No code copied. Deviations: `class A { +x }` on one line
  and nested namespaces are rejected; `direction` is accepted anywhere.
  `tests/pairs/mermaid/own/class-*.expected` (11 pairs) are hand-checked
  facts (`tests/pairs/project_class.lua`), not oracle output.

## mermaid.js (state diagram syntax)

* URL: https://mermaid.js.org/syntax/stateDiagram.html
* Licence: MIT (mermaid-js/mermaid)
* Status: **study-only**. `stateDiagram`/`stateDiagram-v2`, `[*]` start and
  end, transitions with `: label`, `state "Long" as id`, `id : description`
  lines, composites, `<<choice>>`/`<<fork>>`/`<<join>>`, `--` concurrency,
  notes, `direction`, ignored styling. No code copied. Deviations: `[*]` is
  one start and one end node per scope; a composite has no node of its own
  (edges to its id attach to the cluster); `note over` is accepted;
  `classDef`/`class`/`style`/`hide`/`scale`/`title` are ignored. Parsing only
  so far (drawing is a later task).
  `tests/pairs/mermaid/own/state-*.expected` (13 pairs) are hand-checked
  facts (`tests/pairs/project_state.lua`), not oracle output.

## mermaid.js (entity relationship diagram syntax)

* URL: https://mermaid.js.org/syntax/entityRelationshipDiagram.html
* Licence: MIT (mermaid-js/mermaid)
* Status: **study-only**. Entities with `{ type name PK, FK "comment" }`
  bodies, `E["Alias"]`, relationships `A ||--o{ B : label` with all
  cardinality symbols and word forms (`one or zero`, `many(1)`, `1+`, ...),
  `--` identifying versus `..` non-identifying (also `to` versus
  `optionally to`), ignored `classDef`/`class`/`style`. No code copied.
  Deviations: entity names are word characters and inner hyphens (or
  quoted); a relationship label is optional. Parsing only so far (drawing is
  a later task).
  `tests/pairs/mermaid/own/er-*.expected` (11 pairs) are hand-checked facts
  (`tests/pairs/project_er.lua`), not oracle output.

## mermaid.js (pie chart syntax)

* URL: https://mermaid.js.org/syntax/pie.html
* Licence: MIT (mermaid-js/mermaid)
* Status: **study-only**. `pie [showData] [title X]`, `title X`, slices
  `"Label" : value`. No code copied. Deviations: a pie without slices is an
  errbox (mermaid.js draws an empty chart); a negative value is an error;
  drawn as bars, not a circle.
  `tests/pairs/mermaid/own/pie-*.expected` (10 pairs) are hand-checked facts
  (`tests/pairs/project_pie.lua`), not oracle output.

## mermaid.js (gantt chart syntax)

* URL: https://mermaid.js.org/syntax/gantt.html
* Licence: MIT (mermaid-js/mermaid)
* Status: **study-only**. `gantt`, `title`, `dateFormat` (`YYYY MM DD HH mm`
  and `X`; others fall back to `YYYY-MM-DD` with a note), `section`, tasks
  `Title :tags, id, start, end|duration` with `done|active|crit|milestone`,
  `after a b`, `until a`, durations `d w h m s`. `axisFormat`, `tickInterval`,
  `todayMarker`, `excludes`, `includes` are kept and not applied. No code
  copied; date arithmetic is days-from-civil (Howard Hinnant, public domain).
  Deviations: the end date is exclusive; a task without end is an error unless
  it is a milestone; ids are bare words; `after a, b` accepts commas.
  Parsing only so far (drawing is a later task).
  `tests/pairs/mermaid/own/gantt-*.expected` (13 pairs) are hand-checked facts
  (`tests/pairs/project_gantt.lua`), not oracle output.

## mermaid-ascii and graph-easy

* URLs: https://github.com/AlexanderGrooff/mermaid-ascii (MIT),
  https://github.com/ironcamel/Graph-Easy (Perl Artistic/GPL, so
  **study-only**, nothing ported)
* Status: reference for drawing look only; used from task 9 of
  `issue/mermaid.md`. Licence of `mermaid-ascii` to be re-checked before any
  port; none planned.

## plenary.nvim

* URL: https://github.com/nvim-lua/plenary.nvim
* Version: pinned commit in `Makefile` (`PLENARY_REV`)
* Licence: MIT
* Status: test runner only; fetched into gitignored `deps/`, not vendored.

## Pair baseline

Own-input suite `commonmark-own`, run on the macOS host on 2026-11-15:
548/548 pass, 0 skipped (threshold 548 in `tests/pairs/markdown/threshold.lua`).
Expected HTML was generated by `cmark 0.30.3` and `cmark-gfm 0.29.0.gfm.13`
(per-file versions in `tests/pairs/markdown/own/*.meta`).
