# nvim-doc-preview: document model (`document.model`)

Shared tree produced by the Markdown and RST parsers and consumed by
`document/render.lua`. Pipeline and parser rules are in `doc/architecture.md`
(4.2, 4.3).


A node is a plain Lua table `{kind=..., src_start=, src_end=, ...fields}`;
block nodes have `children` (blocks) or `inlines` (inline nodes). The model
is the **union** of the semantics of the supported formats:

* A construct gets an **unprefixed** kind when its meaning is
  format-independent, even if only one format produces it today (e.g.
  `strike`, task-list `checked`): the renderer implements it once and
  another format can start emitting it for free.
* A construct that is **specific to one format**, or whose name collides
  with a different meaning in the other, is **namespaced** with the format
  prefix: `rst:field_list`, `rst:role`, `rst:directive`, `rst:line_block`,
  `md:html_block`, `md:html_inline`. A parser may only emit unprefixed
  kinds and its own prefix.

Every node also has `kind`, `src_start`, `src_end` (architecture 4.2). Complete kind list (the renderer's dispatch table has exactly these keys; the prefixed kind is the `kind` string, e.g. `rst:field_list`):

| Level | Kind | Prefix | Fields | Notes |
|---|---|---|---|---|
| Block | `document` | - | children: blocks | root |
| Block | `heading` | - | level (1-6), inlines | md ATX/setext, rst adornment (level by first appearance) |
| Block | `paragraph` | - | inlines |  |
| Block | `list` | - | ordered, start, tight (bool), children: list_item | md, rst bullet/enumerated. Rendered with `• ` bullets (ascii charset: 0018) or `N. ` numbered from `start`, number column padded to the widest number; children render with `ctx.width` minus the marker width (hanging indent), blank line between items only when not `tight` |
| Block | `list_item` | - | checked (optional bool), children: blocks | `checked` only from md task lists; the marker text becomes `[ ] ` / `[x] ` (after the number for ordered lists) |
| Block | `definition_list` | - | children: items {term inlines, children blocks} | rst; md extension |
| Block | `blockquote` | - | children: blocks | md `>`; rendered with a quote prefix on every line (`│ `, unicode until the charset option, 0018), children laid out at `ctx.width` minus the prefix width, nested quotes shrink per level; a level with no room for the prefix plus one content column drops its prefix, so no line exceeds `ctx.width` |
| Block | `code_block` | - | lang (optional), lines, src_body | fences, indented, literal blocks, `code-block`; diagrams use an engine `lang` (architecture 4.5). `src_body` is the source line of `lines[1]` (container-stripped lines are contiguous in the source). Rendered verbatim (no prefix or box, tabs expanded, no trimming), hard-wrapped at `ctx.width` by display width (nothing clipped), every non-empty row carries a `DocPreviewCode` span; `lang` is not shown (plain code until `core/codeblock`) |
| Block | `table` | - | align (entries nil/`left`/`center`/`right`), header, rows; cells `{inlines}`, colspan/rowspan only from rst grid (unused for md) | md pipe, rst grid/simple. Header and every row hold exactly `#align` cells. Rows are single source lines: header is `src_start`, delimiter `src_start + 1`, body row `i` is `src_start + 1 + i`. Rendered as a box grid (unicode, ascii via `ctx.charset`) fitted to `ctx.width` with wrapped cells; header rows carry `DocPreviewTableHeader`, borders `DocPreviewTableBorder` |
| Block | `thematic_break` | - | (none) | md rule, rst transition; renders as one line of `ctx.width` `─` (unicode until the charset option, 0018) |
| Block | `admonition` | - | kind, title (optional), children: blocks | rst `note`/`warning`/...; md GFM alerts if added |
| Block | `image` | - | alt, target, title (optional), src_start, src_end | md: a paragraph whose only inline is one image (not inside a link, no other text, no trailing hard break) is promoted to this block, also inside quotes and list items; headings and table cells keep inline images. rst `image`/`figure`. Rendered as the placeholder `[image: alt]` (`[image]` for empty alt) wrapped at `ctx.width`, `DocPreviewImage` on every row, one map entry over `src_start`..`src_end`; `target`/`title` are never shown |
| Block | `footnote_def` | - | label (normalised, non-empty), children: blocks, src_start, src_end | md `[^label]: text`; body is blocks (paragraphs, lists, code). Not rendered in place; shown only in the trailing Footnotes section when referenced. An unreferenced definition is not shown. Section entries map to the definition's range |
| Block | `rst:field_list` | rst | children: fields {name inlines, children blocks} |  |
| Block | `rst:line_block` | rst | lines: inline lists |  |
| Block | `rst:directive` | rst | name, args, body (raw lines) | unknown directives, shown as dimmed box |
| Block | `rst:comment` | rst | lines | not rendered |
| Block | `md:html_block` | md | lines, src_body | `src_body` as for `code_block` (row `i` maps to `src_body + i - 1`). Lines verbatim: container prefix stripped, 0-3 columns of indent kept, nothing trimmed or parsed. Rendered like code (tabs expanded, hard-wrapped at `ctx.width`, empty block is one empty row), every non-empty row carries a `DocPreviewHtml` span |
| Inline | `text` | - | value |  |
| Inline | `emph` | - | inlines |  |
| Inline | `strong` | - | inlines |  |
| Inline | `strike` | - | inlines | md only today |
| Inline | `code` | - | value | md code span, rst inline literal |
| Inline | `link` | - | target, title (optional), inlines | md links/autolinks, rst hyperlinks; rendered as text + `[n]` |
| Inline | `image` | - | alt (plain text), target, title (optional) | rendered as the placeholder `[image: alt]` / `[image]` with `DocPreviewImage` (wraps with the surrounding text; inside a link it keeps the underline and `[n]` marker); `target`/`title` never shown |
| Inline | `footnote_ref` | - | label (no range) | only for a label that has a definition; an undefined `[^x]` stays literal text. Rendered as `[^n]` (n by first use, separate from link numbers) with `DocPreviewFootnoteRef` |
| Inline | `softbreak` | - | (none) |  |
| Inline | `hardbreak` | - | (none) |  |
| Inline | `rst:role` | rst | role, text | `:ref:`, `:code:`...; styled text, no resolution |
| Inline | `rst:substitution` | rst | name | shown as source |
| Inline | `md:html_inline` | md | value | atomic raw tag, comment, processing instruction, declaration or CDATA; no range, inner text not parsed; plain text of `value` in the paragraph flow (newlines become spaces) with a `DocPreviewHtml` span |

Mapping examples: Markdown fenced block and RST `code-block`/`mermaid`/`dot`
directive both become `code_block{lang}`; RST `note`/`warning`/... directives
become `admonition{kind}`; RST `:ref:` stays an `rst:role` and the renderer
shows it as styled text (no cross-reference resolution).

Rules for the renderer: it dispatches on `kind` through one table. A
namespaced kind with no handler, or any unknown kind, degrades to its raw
source lines dimmed (via `core/errbox`) and never raises. This keeps format
additions cheap: new kind + handler, or no handler and graceful fallback.
