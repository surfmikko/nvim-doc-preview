# 0009 Thematic break

Status: done

Goal: `***`, `---`, `___` (and spaced variants) render as a horizontal
rule of `ctx.width`.

Touches: `markdown/block.lua` (dispatch precedence), `document/model.lua`
(`thematic_break`), `document/render.lua` (rule line, one map entry),
`tests/pairs/project_html.lua` (`hr`), `tests/{unit,golden,pairs}`.

Brings: rule detection (3+ chars, inner spaces allowed, up to 3 indent) and
the precedence decisions: `---` directly after paragraph text stays a setext
heading (0004), `---` otherwise is a rule; the rule is tested before list
item start so `* * *` never reaches the list code (0011). Glyph defaults to
unicode (`─`) because `ctx.charset` is not plumbed until 0018. Removes the
`---` paragraph-fallback comment left by 0004.

Tests: unit (precedence against setext and, once present, text), own-input
pairs for "Thematic breaks" (cmark oracle), golden at width 40.

References: CommonMark "Thematic breaks" and its interplay with "Setext
headings" and "List items" (behaviour only). Port: `markdown-it` (MIT)
`hr.js` or `commonmark.js` (BSD-2). `doc/architecture.md` 6.1;
`doc/document-model.md` (`thematic_break`).

Depends on: 0004 (setext precedence). Before 0011 (lists).

Out of scope: ascii charset (0018), rules inside containers (0010, 0011).

## Tasks

- [x] 1. Model and renderer: `document/model.lua` gains
   `M.thematic_break(src_start, src_end)` (no fields, kind registered,
   `validate` accepts it); `document/render.lua` gains a `thematic_break`
   handler: one line of `ctx.width` (default 80) `─` characters, one map
   entry, no span. Glyph is a local constant with a comment pointing to
   0018 (charset). Unit tests in `tests/unit/document_spec.lua` on
   hand-built trees: width 40 and default width, rule between two
   paragraphs (blank separator lines as for other blocks), map entry,
   width 1.
- [x] 2. Block rule and precedence in `markdown/block.lua` (+ unit tests):
   add `thematic(line)`: up to 3 columns of indent (`expand_indent`, tab
   expanded), then 3 or more of the same char `*`, `-` or `_`, spaces and
   tabs allowed between and after, nothing else on the line (`**-` and
   `-*-` are not rules). In `parse`: a rule line flushes the open
   paragraph and adds a `thematic_break` block (extend `pending`/`build`
   with a `rule` entry, `src_start == src_end == i`); it is tested before
   any list start (`* * *` must not reach 0011). Setext precedence: `-`
   run (no inner spaces) directly under an open paragraph stays a level 2
   underline (so `Foo\n---` and `Foo\n--` are headings), `- - -` and
   `* * *` under a paragraph are rules, a `---` with no open paragraph
   (start, after blank, after a heading or rule) is a rule; `===` is never
   a rule. ATX still interrupts first. Remove the "until 0009" comment in
   `setext` and update the file header comment (thematic breaks now
   handled). Keep functions small; the file must stay under the 400 line
   gate. `tests/unit/markdown_block_spec.lua`: all three chars, spaced
   variants, 2 chars is not a rule, indent 0-3 vs 4 (4 stays a paragraph
   fallback), mixed chars, trailing text, source range, interrupts a
   paragraph, `---` after paragraph is a heading, `- - -` after a
   paragraph is a rule, `---` after a blank line is a rule, consecutive
   rules, rule right after a heading. Both scroll integration specs keep
   passing (they use no rules; confirm).
- [x] 3. Golden fixtures `tests/golden/markdown/thematic-break.in|.out`
   (`***`, `---`, `___`, spaced `* * *`, rule between paragraphs, rule
   after a setext heading, `Foo` over `---` stays a heading) at width 40
   (`.width` file as in `inline-wrap`, or the golden default if it is 40);
   run `UPDATE_GOLDEN=1 make test-golden` and review the diff by hand
   (rule lines are exactly 40 columns wide, no `.spans` file since no
   spans).
- [x] 4. Pair projection: `tests/pairs/project_html.lua` projects
   `thematic_break` to `<hr />` (cmark's form); `normalize` unchanged.
   Extend `tests/unit/pairs_project_spec.lua` with hand-built and parsed
   cases (`***` -> `<hr />`, rule between paragraphs, `Foo\n---` still
   `<h2>`).
- [x] 5. Own pair inputs and skip manifest: add about 15 small inputs
   under `tests/pairs/markdown/own/` named `thematic-*.in` (written
   fresh, no spec text): the three chars, spaced variants, 2 chars, more
   than 3 chars, indent 1-3, indent 4 (skip: indented code, later slice),
   mixed chars, trailing spaces, trailing text, rule interrupting a
   paragraph, rule after setext heading, `---` after paragraph (heading),
   `- - -` after paragraph, rule at start and end of document, tab
   between chars. Extend `tools/oracle/commonmark-own` only if it needs
   changes (it should pick up new `.in` files unchanged; check). Remove
   `own/setext-dash-no-paragraph` from `tests/pairs/markdown/skip.lua`
   (thematic break now implemented; a stale skip fails the run) and skip
   any new case that needs an unimplemented feature with a reason
   (`lists: 0011`, `indented code: later slice`). The sandbox has no
   `cmark`, so no `.expected` exists yet; check each input by hand against
   the expected HTML via the projection (task 4).
   Done: 22 `thematic-*.in` written, stale skip removed, `thematic-indent-4`
   skipped (indented code); `commonmark-own` needs no change; projection of
   every input checked by hand. Without `.expected` the runner reports them
   pending, suite passes.
   (host verify: run `tools/oracle/commonmark-own` with `cmark`
   installed and commit the new `.expected`/`.meta` files.) (verified on host 2026-11-15)
- [x] 6. Pair baseline (host verify: `make test` on the host with `cmark`
   and the generated expectations): run the oracle, run `make test-pairs`,
   triage every failure (fix the parser, or add a `skip.lua` entry with a
   reason; deviations are reviewed, not hidden), raise `threshold.lua`
   `own` to the achieved pass count, record the thematic-break counts in
   `doc/references.md` if it keeps per-section counts, then mark tasks 5
   and 6 `[x]`.
   (host steps: `port install cmark`; `sh tools/oracle/commonmark-own`;
   `make test-pairs`; triage; update threshold and counts; commit.) (verified on host 2026-11-15)
- [x] 7. Docs and wrap-up: `doc/plan.md` index row 0009 set to the real
   status; `doc/document-model.md` `thematic_break` note gets the
   rendering (`ctx.width` rule, unicode glyph until 0018) if not already
   implied; add the CommonMark thematic-break reference note (behaviour
   only; port source if any code was ported, with header comment and
   `NOTICE` entry) to `doc/references.md`; update the "Brings" Status
   line to `done` once 5-6 are verified (`in progress` until then). Run
   `agent-test --full` (must pass) and the stylua and luacheck gates
   where runnable (`make format-check lint size banned`; if stylua or
   luacheck are missing in the sandbox, mark `(host verify: make ci)`).
   Done: docs updated, `agent-test --full` passes, `size` and `banned` clean.
   (host verify: `make ci`; stylua and luacheck are not installed in the
   sandbox. After tasks 5-6 pass on the host set Status to `done`.) (verified on host 2026-11-15)

## Done when

`***`, `---` and `___` (and spaced variants) render as a rule of
`ctx.width` `─`; `Foo` over `---` is still a setext heading; `* * *`
never reaches list code; `agent-test --full` passes and the quality gates
are clean.
