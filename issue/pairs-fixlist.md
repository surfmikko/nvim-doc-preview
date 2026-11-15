# Pairs fix list

Status: done

Goal: bring the `commonmark-own` reference-pair suite from 543/548 to
548/548 after the first host run with oracle `.expected` files, then lock in
the baseline.

Source: `pairs.log` (host `make test-pairs`). Full analysis:
`.claude-data/var/report/tasks-pairs-fixlist-20261114-2130.md`.

Result: only the footnotes and tables slices fail (5 cases, 4 root causes).
Thematic break, block quote, lists, code, html and images pass fully; no
`skip.lua` entries are needed.

## Tasks

### Footnotes

- [x] 1. Projection mismatch, `own/gfm-footnote-body-list-code`: when a
  footnote body ends in a non-paragraph block (list then code), cmark-gfm
  puts the backref bare after it (`</code></pre>\n<a ... >↩</a>\n</li>`);
  we emit `<p> <a ...></p>` (extra `<p>` and leading space). Fix in
  `tests/pairs/project_html.lua` (`entry_html` non-paragraph branch and the
  leading space in `backref_link`; keep the multi-reference `<sup>` form).
  Not a parser bug.

- [x] 2. Oracle flags, `own/gfm-footnote-table-cell`: `gfm-footnote-*`
  inputs run `cmark-gfm` without `--extension table`, so the expected has no
  table (`<p>| a | b |...</p>`) while our table output is the correct GFM
  result. Fix in `tools/oracle/commonmark-own` (add `--extension table` for
  footnote inputs, or at least `gfm-footnote-table-*`), update the
  sentence in `doc/testing.md` (Markdown decision), regenerate that case's
  `.expected` and `.meta` on the host. (host verify: oracle re-run for that
  case, diff against our actual)
  Done: oracle script and doc/testing.md updated (footnote inputs now add
  `--extension table`). Host: run `tools/oracle/commonmark-own`, then
  `git diff tests/pairs/markdown/own/gfm-footnote-table-cell.*` should show
  a `<table>` expected and the new command in `.meta`; `make test-pairs`
  must then pass that case. (verified on host 2026-11-15)

### Strikethrough

- [x] 3. Parser bug, `own/gfm-strike-mismatch`: for
  `~~a~ and ~a~~ ...` cmark-gfm yields no strikethrough; we pair the outer
  `~~` runs and give `<del>a~ and ~a</del>`. Fix in
  `lua/doc_preview/markdown/inline.lua` (`matches`/`find_opener`): a `~`
  closer whose nearest `~` opener has a different run length must not keep
  searching further back (consume or deactivate that opener). Confirm the
  rule with `cmark-gfm` on a few variants (`~~a~ b~~`, `~a~~ b~`) and keep
  the other `gfm-strike-*` pairs green; add a unit test.

### Tables

- [x] 4. Parser bug, `own/gfm-table-no-outer-pipes` and
  `own/gfm-table-trailing-pipe-only` (one cause): `- | -` and `- | - |` as
  the delimiter row start with a bullet marker, which interrupts the
  paragraph in cmark-gfm (expected: paragraph plus list, no table); we
  build a table. Fix in `lua/doc_preview/markdown/block.lua` (`table_align`)
  or `markdown/table.lua` (`delimiter`): reject the delimiter row when the
  line is a list item start (`container.item_marker(line, true)`); `-|-`,
  `| - |` and `:-` rows must still make tables. Add a unit test. Fallback
  only if too intrusive: two `skip.lua` entries with reason "cmark-gfm lets
  a list start win over the delimiter row (GitHub does the same)".

### Close-out

- [x] 5. (host verify: `make test-pairs`, `make ci`) Re-run `make test-pairs`
  on the host (regenerate oracle output first if task 2 changed it, run
  `tools/oracle/commonmark-own`). Expect 548/548, skipped 0. Raise
  `tests/pairs/markdown/threshold.lua` from `own = 0` to the passing count,
  and replace the "Not yet recorded" text in `doc/references.md` "Pair
  baseline" with per-section pass/skip counts plus the `cmark` and
  `cmark-gfm 0.29.0.gfm.13` versions (also fill the cmark version line in
  the "cmark" entry). (verified on host 2026-11-15: commonmark-own 548/548, threshold 548, baseline in `doc/references.md`)
