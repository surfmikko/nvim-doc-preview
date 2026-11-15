# 0001 Testing framework

Status: done

Goal: `make test` runs unit and integration specs headless, both report
a pass, and a failing spec makes the run exit non-zero. No plugin
implementation yet.

Touches: `tests/`, `Makefile`, `.gitignore`, docs.

## Tasks

- [x] 1. Review the existing `Makefile` (`deps`, `test-unit`, `test-integration`,
   `clean`): `deps` already clones plenary.nvim into gitignored `deps/`.
   Pin it to a commit/tag so runs are reproducible. Plenary is pure Lua,
   so `deps/` is safe to share between host and sandbox.
- [x] 2. `tests/minimal_init.lua`: add repo root and `deps/plenary.nvim` to
   `runtimepath`, load plenary; no user config.
- [x] 3. Unit layer: `tests/unit/smoke_spec.lua` with one passing
   `describe`/`it`. `make test-unit` runs it headless.
- [x] 4. Integration layer: `tests/integration/smoke_spec.lua` with one
   passing spec that runs in real headless Neovim (asserts it is running
   headless and a buffer can be created). The child-Neovim RPC helper
   (`doc/testing.md` 1.1) is **not** built here; it comes with the first
   issue that needs it.
- [x] 5. `make test` runs both layers; non-zero exit on any failure. Verify
   once by temporarily adding a failing spec, then remove it.
- [x] 6. `.gitignore` covers `deps/`. Nothing platform-specific is written
   to shared locations (plenary is the only download; no build output).
   Document the commands in `README.md` and `doc/testing.md` 1.

## Done when

Fresh checkout + `make test` prints two passes and exits 0; the
deliberate-failure check exits non-zero.

## Out of scope

Pair runner, golden runner (`UPDATE_GOLDEN`), CI config, quality gates
(`doc/testing.md` 5), oracle tools, any `lua/doc_preview/` code.
