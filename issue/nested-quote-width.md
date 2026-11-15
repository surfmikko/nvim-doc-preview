# Nested quote width
Status:       done
Goal:         Deeply nested block quotes never render lines wider than the window width.
Touches:      `lua/doc_preview/document/render.lua` (`blockquote`), `tests/unit/fuzz_spec.lua`, `doc/document-model.md`
Tasks:        see below
Done when:    fuzz spec checks 300 nested quotes at widths 1, 2, 3, 20 and 1000; `agent-test` green.
Out of scope: list nesting at narrow widths; a parser depth cap.

Decision: when `width - prefix width < 1` a quote level drops its prefix and
lays its children out at the full width (a visual cap on nesting depth),
instead of clamping content to 1 column and overflowing. Rejected: truncating
prefixes (loses the quote marker semantics at every level) and clamping the
total prefix (needs cross-level state).

## Tasks

- [x] 1. `blockquote`: drop the prefix when it leaves no content column; spec note in `doc/document-model.md`; fuzz "deep quotes" at narrow widths.
