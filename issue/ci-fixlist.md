# ci-fixlist `make ci` failures

Status: done

Source: `ci.log` (`make ci` on the host). Full analysis and raw diffs:
`.claude-data/var/report/tasks-ci-fixlist-20261114-1200.md`.

Only the first target, `stylua --check lua tests plugin`, ran: `make` stopped
at its failure, so luacheck, size, banned-API and tests produced no output and
are unverified (not known to pass). Pair failures are tracked in
`issue/pairs-fixlist.md` (written separately from `pairs.log`); do not
duplicate them here.

stylua is not installed in the sandbox. The proper fix is `make format` on
the host (task 1). A coder may instead hand-format to match the diffs in the
report (wrap long table constructors/`or` chains one operand per line,
break `local x =` before a long RHS, prefer double quotes unless the string
contains `"`), but must not claim `[x]`; mark `[~]`.

## Tasks

- [x] 1. stylua formatting, `lua/` (host verify: `make format` then `stylua --check lua`): `markdown/footnote.lua` (1 hunk, return of table plus `j`), `markdown/html.lua` (3: `ipairs({...})` table, `block_end` `or` chain, `entry =` wrap), `core/table.lua` (1), `markdown/container.lua` (3: `scan, atx, ... =` wrap, two returns of table plus `j`), `document/model.lua` (1: `footnote_def`), `markdown/block.lua` (4: `starts_block` `or` chain, `add` pending wrap, and two more in `scan`), `sync.lua` (2), `document/render.lua` (1), `markdown/inline.lua` (1). Report lists exact hunks.
- [x] 2. stylua formatting, `tests/` (host verify: `make format` then `stylua --check tests`): `tests/pairs/markdown/skip.lua` (2), `tests/pairs/project_html.lua` (3), `tests/unit/document_spec.lua` (14), `tests/unit/markdown_block_spec.lua` (7, incl. `'<a href="x'` quote style), `tests/unit/markdown_footnote_spec.lua` (1), `tests/unit/pairs_project_spec.lua` (7).
- [x] 3. Confirm tasks 1-2 are formatting-only: no behaviour change, `agent-test` still passes in the sandbox after any hand edits.
- [x] 4. Re-run `make ci` on the host (host verify: format-check, lint, size, banned, test all reach the end). Output not yet seen for luacheck (warnings to be listed as file:line, code, fix), `tools/` size gate (module-line limit per `doc/testing.md` 5) and banned-API gate, and the test target; append any new failures as tasks here (pair failures go to `issue/pairs-fixlist.md`), fix, and repeat until `make ci` exits 0 with a fresh `ci.log`. (verified on host 2026-11-15)

- [x] 5. luacheck (22 warnings in the second `ci.log`): fixed in the sandbox by
  splitting functions into small helpers (complexity 10 limit kept, no ignores),
  new modules `markdown/scan.lua` and `markdown/leaf.lua`, plus test cleanups.
  Complexity was counted by hand because luacheck is not installed here. Host
  verify: `make lint`, then `make ci`; any remaining warning becomes a new task. (verified on host 2026-11-15)

- [x] 6. Third `ci.log` (2 luacheck warnings): removed unused `BOOL` in `config.lua`; split `mutate` in `tests/unit/fuzz_spec.lua` into `mutate_once` plus an op table (complexity under 10 by hand). `agent-test` passes. Host verify: `make ci`. (verified on host 2026-11-15)
