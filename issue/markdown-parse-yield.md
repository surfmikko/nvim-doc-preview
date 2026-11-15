# Markdown parse: quadratic lazy continuation and cancellation
Status:       planned
Goal:         Long lazy-continuation quotes/items parse in linear time and the Markdown parser yields, so the UI does not freeze and `job.cancel` works.
Touches:      `lua/doc_preview/markdown/container.lua` (`take_quote` ~370, `ends_item` ~414), `lua/doc_preview/markdown/scan.lua`, `doc/architecture.md` (layering decision), `tests/unit/` markdown specs
Source:       project review finding 2, report `.claude-data/var/report/reviewer-project-20261115-1201.md`
Parallel:     touches `markdown/` only; independent of the other review issues. Do not run alongside other work on `markdown/container.lua` or `scan.lua`.

## Tasks

- [x] 1. Decide and document how `markdown/` yields: either allow `markdown/` to require `core.job`, or pass a yield callback into the parser; update `doc/architecture.md` (layering rules near line 113, pipeline/yield text near 383) accordingly. Add `job.yield_point()` (or the callback) in the main loop of `scan.scan`. Unit test: a long parse inside a job yields at least once and a cancel during parse aborts it.
- [x] 2. `container.lua`: make open-paragraph tracking incremental so `take_quote` and `ends_item` no longer rescan the whole inner container per lazy line (O(n^2) now: 4000 lazy lines = 6 s). Output must be unchanged: existing golden and unit tests pass. Add a timing regression test (3000 lazy lines for both `> a` and `- a` cases under a generous time bound).

Done when: new tests pass, golden/unit suites unchanged, `make check-size`/banned-API gates still pass (400-line module limit).
Out of scope: fuzz spec (`robustness-tests`).
