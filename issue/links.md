# 0007 Links

Status: done

Goal: inline links, autolinks and reference-style links render as their text
plus a marker `[n]`, with the targets listed as a numbered "Links" section
at the end of the document. Inline images are parsed (`![alt](src)`) and
shown as their alt text until 0015 renders the placeholder.

Brings: `markdown/unescape.lua` (character references moved out of
`inline.lua`), `markdown/link_syntax.lua` (pure string helpers: labels,
destinations, titles, autolinks, link reference definitions),
bracket handling in `markdown/inline.lua`, a two-pass `markdown/block.lua`
(definitions are collected before any inline text is parsed),
`link`/`image` in the model, `document/linklist.lua` (numbering and the
Links section), link groups, own-input pairs, golden fixtures.

Touches: `lua/doc_preview/{markdown/unescape,markdown/link_syntax,markdown/inline,markdown/block,document/model,document/linklist,document/render,core/highlight}.lua`,
`tests/{unit,golden,integration,pairs}/`, `doc/{architecture,document-model,references,plan}.md`.

Depends on: 0006 (inline parser, flattening renderer, styled wrap).

References (recorded in `doc/references.md`): CommonMark "Links", "Images",
"Autolinks", "Link reference definitions"; GFM "Autolinks (extension)"
(decided out of scope). Behaviour only, no spec text or examples copied
(CC BY-SA). Pair inputs are written here; expectations come from `cmark`.
`doc/architecture.md` 4.2, 4.3; `doc/document-model.md`.

Decisions taken for this slice:

* No code is ported (bracket-stack idea studied in commonmark.js, BSD-2).
* Model: `link{target, title?, inlines}`, `image{target, title?, alt}` where
  `alt` is the plain text of the description (markup removed, breaks become
  spaces). Both are inline kinds without source range.
* Numbering (shared with 0016): link numbers and footnote numbers are
  **separate sequences**. Links are numbered at render time in order of
  first use, one number per distinct `target` (title is ignored); the
  marker is `[n]`. 0016 numbers footnotes in its own sequence and its own
  marker style (`[^n]`), so it never renumbers links. Recorded in
  `doc/architecture.md` 4.3.
* The Links section is `Links` (heading group `DocPreviewH2`) plus one
  `[n] target` line per entry (wrapped, long targets hard-split). The title
  attribute is not shown. Each entry maps to the source line where the
  block of its first use starts (inlines carry no lines), the section
  title to the first entry's line.
* Definitions: first definition of a label wins, labels match after
  trimming, whitespace collapse and ASCII lowercasing. Only the start of
  a paragraph can hold definitions; a paragraph made only of definitions
  disappears. Not extracted from setext headings (limit).
* References resolve the whole document, so a definition may follow its use.
* Inline `<...>` that is not an autolink stays literal text (raw inline
  HTML is 0013). GFM bare URL autolinks are out of scope.
* Image: parsed everywhere a link can be, alt text rendered as plain
  text for now; `[image: alt]` is 0015.
* `core/out.lua` gets no `links` field now: `<CR>` on a link is 0008, which
  adds it together with the span data it needs.
* Limits: ASCII case folding for labels, no Unicode normalisation.
* Groups: `DocPreviewLink` (link `Underlined`) on the link text,
  `DocPreviewLinkMark` (link `Special`) on `[n]`, both `default = true`.

## Tasks

- [x] 1. Model: `document/model.lua` gains `link(target, title, inlines)`
   and `image(target, title, alt)`, registers both as inline kinds;
   `validate` recurses into link `inlines`. Unit tests in
   `tests/unit/document_spec.lua`.
- [x] 2. Move character references: `decode` and `utf8_char` leave
   `markdown/inline.lua` for `markdown/unescape.lua`, which also exports
   `unescape(s)` (backslash escapes plus references, for destinations and
   titles). Behaviour unchanged: the existing inline specs stay green; new
   unit tests `tests/unit/markdown_unescape_spec.lua`.
- [x] 3. `markdown/link_syntax.lua`, part 1: `label` (bracketed raw label,
   no unescaped brackets, at most 999 chars, not blank), `normalize`,
   `destination` (angle form, bare form with balanced parentheses, escapes),
   `title` (three quote styles), `inline_tail` (`(dest "title")` with up to
   one line ending of whitespace). Unit tests
   `tests/unit/markdown_link_syntax_spec.lua`.
- [x] 4. `markdown/link_syntax.lua`, part 2: `autolink` (URI and email
   forms) and definition parsing (`definition(s)`, `extract(text, refs)`:
   strips leading definitions from paragraph text, fills `refs`, returns
   the rest and the consumed line count; title on its own line, invalid
   title falls back to a definition without title). Unit tests in the same spec.
- [x] 5. `markdown/inline.lua`, part 1: `[`, `![`, `]` handlers with a bracket
   stack, inline links and images, link text is processed in isolation (own
   emphasis scope), links do not nest (outer `[` becomes inactive), images
   may nest links; `<` autolinks. Unit tests in
   `tests/unit/markdown_inline_spec.lua` (title, angle destination, nesting,
   emphasis inside text, unclosed, autolink literal cases).
- [x] 6. `markdown/inline.lua`, part 2: reference links and images through
   `inline.parse(s, refs)`: full `[text][label]`, collapsed `[text][]`,
   shortcut `[text]`; a failed full reference does not fall back to shortcut;
   case-insensitive labels. Unit tests in the same spec.
- [x] 7. `markdown/block.lua` two-pass: paragraphs and headings are collected
   first, definitions extracted from paragraph starts in document order
   (first wins, source range start moves past consumed lines, empty
   paragraph dropped), then inline parsing with `refs`. Unit tests in
   `tests/unit/markdown_block_spec.lua`.
- [x] 8. Pair projection: `tests/pairs/project_html.lua` projects `a` (with
   `title`) and `img` (`alt`, `title`) with cmark-style href escaping.
   Unit tests in `tests/unit/pairs_project_spec.lua`.
- [x] 9. Renderer, groups, golden and integration: `document/linklist.lua`
   (registry, `[n]` numbering, Links section with map entries),
   `render.lua` flattens `link` (text plus marker, groups) and `image`
   (alt text) and appends the section; `core/highlight.lua` groups;
   `doc/architecture.md` 4.3 numbering decision and `doc/document-model.md`.
   Unit tests (`tests/unit/render_links_spec.lua`, `highlight_spec`), golden
   fixtures `links-inline`, `links-reference` (+ `.spans`),
   `tests/integration/links_spec.lua` (preview text, extmarks, source map).
- [x] 10. Own pair inputs: `links-*`, `image-*`, `autolink-*`, `refdef-*`
   inputs in `tests/pairs/markdown/own/`; `doc/references.md`. No
   `.expected` files: no `cmark` in the sandbox (pending in the runner). The
   projected HTML of every input was checked by hand against CommonMark
   behaviour. Host check: `tools/oracle/commonmark-own`. (verified on host 2026-11-15)
- [x] 11. Pair baseline (host): run `tools/oracle/commonmark-own`, commit the
   new `.expected`/`.meta` files, run `make test-pairs`, triage failures (fix
   the parser or add a `skip.lua` entry with a reason), raise
   `threshold.lua`, record counts in `doc/references.md`, run `make ci`,
   then mark tasks 10 and 11 `[x]`. (verified on host 2026-11-15: commonmark-own 548/548, threshold 548, baseline in `doc/references.md`)

## Done when

`:DocPreview open` on a Markdown file shows links, autolinks and reference
links as styled text followed by `[n]`, the Links section at the end lists
each distinct target once in first-use order, definitions vanish from the
text and resolve even when they come after the use; `make ci` passes; the
pair suite reports the new cases (pending until the oracle ran).

## Out of scope

Image placeholder (0015), footnotes (0016), raw inline HTML (0013), `<CR>` on
a link (0008), GFM bare URL autolinks, Unicode case folding of labels.
