# Robustness tests
Status:       planned
Goal:         The "never throws, hangs or exceeds width" gate from `doc/testing.md` section 5 exists, and the session `on_error` path is tested.
Touches:      `tests/unit/` or `tests/integration/` only (new specs); no source changes expected
Source:       project review finding 7, report `.claude-data/var/report/reviewer-project-20261115-1201.md`
Parallel:     touches tests only, so it can be written in parallel, but the fuzz spec fails until `nested-render-crash` and `markdown-parse-yield` are done; merge it after them.

## Tasks

- [x] 1. Session test for the render-failure path (`session.lua:117` `on_error`): stub the renderer to throw, assert a notification is raised, `s.job` is reset, and the next edit renders normally. Add to `tests/integration/session_spec.lua` or a new spec.
- [x] 2. Fuzz/mutation spec per `doc/testing.md` section 1 layer 5: a deterministic (seeded) generator and mutator over the existing golden/pair inputs plus crafted cases (deep nesting, long lazy runs, huge tables, unterminated fences/fences in containers, odd Unicode). Assert parse + render never throw, finish within a time bound, and no output line exceeds the width. Keep it fast enough for the 5 minute `agent-test` limit. Depends on `nested-render-crash` and `markdown-parse-yield` being done.

Done when: both specs pass in `agent-test`.
