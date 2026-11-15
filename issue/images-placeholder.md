# 0015 Images placeholder

Status: done

Goal: images render as `[image: alt]` placeholders, as a block when the
paragraph is a single image and inline otherwise.

Touches: `markdown/block.lua` (promote a paragraph consisting of one image
to a block `image`), `document/render.lua` (placeholder text, dim span),
`document/model.lua`, `core/highlight.lua`, `tests/pairs/project_html.lua`
(`img` alt), `tests/{unit,golden,pairs}`.

Brings: only rendering and promotion. Inline image parsing stays in 0007
(avoids a conflict in `markdown/inline.lua`).

Tests: unit; golden (block and inline, empty alt, wrapped alt text);
own-input pairs for "Images" (cmark oracle), rendering part only.

References: CommonMark "Images" (behaviour only). `doc/architecture.md`
4.3 (placeholder), 6.1; `doc/document-model.md` (`image`).

Depends on: 0007 (image parsing).

Out of scope: any image display protocol, remote fetch, `src` handling.

## Decisions for the plan

- Inline parsing already exists (0007): `inline.lua` builds `model.image(target,
  title, alt)` (alt is plain text, markup stripped). `inline.lua` (366 lines)
  is not touched. Today `render.lua` `leaf_text` shows the bare alt.
- Placeholder text: `[image: alt]`; empty alt gives `[image]`. Newlines in alt
  count as spaces (existing `leaf_text` rule). New group `DocPreviewImage`
  (`link = "Comment"`, `default = true`, in `core/highlight.lua`) covers the
  whole placeholder. `src`/`title` are never shown. An image inside a link
  keeps the link underline and the `[n]` marker; the image group sits on top.
- Inline case: `render.lua` `flatten` pushes the placeholder with the group
  (so it wraps with the paragraph, headings and table cells); `leaf_text`
  stops returning `alt` for images. Keep `render.lua` under 400 lines (285
  now); put the placeholder helper in a tiny function there, or in
  `table_render.lua`-style helper only if needed.
- Block case: block kind `image` (fields `target`, `title`, `alt`, `src_start`,
  `src_end`; registered in `model.kinds`, `validate` checks `alt` string and
  `target`; check that `validate` keeps telling block and inline `image` apart,
  inline nodes have no source range). Constructor `M.image_block(...)`
  or equivalent. Rendered as the placeholder wrapped with `text.wrap_styled`
  at `ctx.width`, one map entry over all rows (`src_start`..`src_end`), group
  on every row.
- Promotion in `markdown/block.lua` `build`, after `inline.parse`: a paragraph
  whose inline list is exactly one `image` node becomes the block (no setext
  or heading involvement, no promotion for headings, table cells or list
  tightness changes: `is_tight` works on pre-build entries and is unaffected).
  Anything else around the image (text, a second image, a trailing hard
  break) stays an inline image in a paragraph. Works inside quotes and list
  items through the recursive `build`. `block.lua` is at 306 lines.
- Pair projection: `tests/pairs/project_html.lua` projects the block `image`
  as `<p><img src=".." alt=".." /></p>` (cmark output for a lone image), so
  pair output is identical with and without promotion. The 9 existing
  `image-*`/`refdef-image` own inputs stay valid.
- No oracle change: cmark is not in the sandbox, new own inputs are
  host-verify only (expectations via `tools/oracle/commonmark-own`, existing
  `*.in` case pattern).

## Tasks

- [x] 1. Model, highlight and renderer (+ unit tests). `document/model.lua`:
   block `image` kind, constructor, `validate` cases (missing alt/target,
   inline vs block). `core/highlight.lua`: `DocPreviewImage` in `setup`
   (`tests/unit/highlight_spec.lua`). `document/render.lua`: inline image in
   `flatten` becomes `[image: alt]`/`[image]` with the group; new block
   handler wraps the placeholder at `ctx.width`, group on each row, one map
   entry. Unit tests in `tests/unit/document_spec.lua` (and
   `render_links_spec.lua` for the link case) on hand-built trees: inline in
   a paragraph, empty alt, alt with newline, long alt wrapped across rows
   with spans on each row, no row wider than `ctx.width` (width sweep), wide
   characters in alt, image in a link (underline, `[n]` marker), image in a
   heading and a table cell, block image exact output, block image in a
   quote and list item, map entry covers every row. `render.lua` stays under
   400 lines.
- [x] 2. Promotion and pair projection (+ unit tests). `markdown/block.lua`
   `build`: a paragraph that is exactly one image becomes the block `image`
   (range kept). `tests/pairs/project_html.lua`: project the block as
   `<p><img .../></p>`; extend `tests/unit/pairs_project_spec.lua`. Unit tests
   in `tests/unit/markdown_block_spec.lua`: lone image promoted, with title,
   reference image `![a][r]`, empty alt, multi-line source (range
   `src_start`..`src_end` at line > 1), surrounding spaces still promoted,
   text before/after, two images, image in a link (not promoted: the
   paragraph's single node is a link), trailing hard break, heading with an
   image (unchanged), image inside a quote and a list item (promoted), tight
   list with a lone-image item. `block.lua` stays under 400 lines.
- [x] 3. Golden and integration. Golden fixtures
   `tests/golden/markdown/images-*.in|.out|.spans` at width 40 (generate with
   `UPDATE_GOLDEN=1 make test-golden`, review by hand): `images-block` (lone
   image, with title, reference form), `images-inline` (inside text, in a
   link with the Links list, in a heading, in a table cell), `images-empty`
   (empty alt), `images-wrap` (long alt wrapped, in a quote). Assert no line
   wider than 40 and `DocPreviewImage` spans present. Integration: extend an
   existing spec or add `tests/integration/images_spec.lua` (pattern of
   `table_spec.lua`): buffer with block and inline images renders, extmarks
   for `DocPreviewImage`, scroll/cursor mapping from the image source line
   lands on its row and back, including a wrapped placeholder. Existing
   golden and scroll specs keep passing.
- [x] 4. Docs. `doc/document-model.md` (block `image` row: fields, promotion
   rule, placeholder; inline `image` row: drop "until then"),
   `doc/architecture.md` 4.3 (placeholder form, empty alt, group, wrapping),
   6.1 (promotion rule), 7 (`DocPreviewImage`), `doc/references.md`
   (CommonMark "Images" behaviour notes for this slice, no code ported),
   `doc/testing.md` if the own-input section lists categories;
   `doc/plan.md` row 0015 `in progress` when work starts and updated at the
   end (to `done` once task 5 passes on the host); this file's Status
   likewise. Update the stale `leaf_text` comment in `render.lua`.
- [x] 5. (host verify: oracle and pair baseline) Add about 10 own inputs
   `tests/pairs/markdown/own/images-block-*.in` (fresh, no spec text): lone
   image, with title, reference image, empty alt, alt with emphasis, wrapped
   multi-line source, image plus trailing text, two images, image in a link,
   in a quote and a list item; hand-check each through the projection. Host
   needs `cmark`: `sh tools/oracle/commonmark-own` generates the
   `.expected`/`.meta`; confirm no diff to existing `.expected` files;
   `make test-pairs`, triage failures (parser fix or `skip.lua` with reason,
   never hidden), raise `threshold.lua` `own` to the achieved count, record
   counts in `doc/references.md` (Pair baseline). Mark `[~]` until run on the
   host.
   Sandbox: 10 inputs `images-block-{lone,title,reference,empty-alt,
   alt-emphasis,multiline,trailing-text,two,in-link,container}.in` written and
   hand-checked through the projection (all give the expected cmark-style
   HTML; the one doubt is `multiline`, where cmark may emit a newline instead
   of a space in `alt`). Host: `sh tools/oracle/commonmark-own`, check `git
   diff` shows no change to existing `.expected`, `make test-pairs`, triage
   (fix or `skip.lua` with reason), set `threshold.lua` `own` to the count,
   record in `doc/references.md` Pair baseline. (verified on host 2026-11-15)
- [x] 6. Final gates. In the sandbox: `agent-test --full` passes and
   `make size banned` clean (400-line gate: `render.lua`, `block.lua`).
   (host verify: `make ci` for stylua and luacheck, `make format-check
   lint`, not installed in the sandbox). Do 5 then 6 in one host round-trip,
   then set `doc/plan.md` and this file's Status to `done`.
   Sandbox done: `agent-test --full` passes, `make size banned` clean. (verified on host 2026-11-15)

## Done when

Images render as `[image: alt]` placeholders, as a block when the paragraph is
a single image and inline otherwise, wrapped to `ctx.width`, dimmed, and map to
their source lines; golden, integration and unit tests pass; own pair inputs
agree with the oracle; `agent-test --full` passes and the gates are clean.
