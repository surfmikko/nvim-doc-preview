# 0005 Quality gates

Status: done

Goal: `make ci` runs style, lint, complexity, module-size and banned-API
checks over `lua/` and `tests/` and fails on any violation; the existing
code passes.

Touches: `Makefile`, `stylua.toml`, `.luacheckrc`, `tools/` (setup and check
scripts), `README.md`, `doc/testing.md` 5 and 7 (change "planned" to
"implemented"), existing `lua/` and `tests/` files (formatting and lint
fixes only, no behaviour change).

Brings: `make format-check`, `make lint`, `make size` (400 lines per file in
`lua/`), `make banned` (grep for `os.execute`, `io.popen`, `vim.system`,
`jobstart`, `load`, `loadstring`; `require` outside `doc_preview`), `make
ci` = those plus `make test`; per-platform tool install hints
(`doc/testing.md` 7: luarocks `--tree`, `cargo install --root`, MacPorts);
luacheck `max_cyclomatic_complexity` 10 (warning 561), `vim` global allowed.
`make sast` (optional, Semgrep) is not required here.

Tests: the gates are the tests; add a spec or script check that the banned-API
grep catches a planted violation in a temp file. Existing specs still pass
after reformatting.

References: `doc/testing.md` 5, 5.1 (decision: banned-API grep is the
required security gate), 7; `CLAUDE.md` (Makefile POSIX sh, GNU/BSD make).
No ported code, no `doc/references.md` entry.

Depends on: 0004 (so the first parser files are formatted once). Goes
before 0006 so later slices land lint-clean.

Notes: stylua and luacheck are not in the sandbox image and there is no
cargo, luarocks or C compiler. Sandbox setup used (outside the repo, in
`.claude-data/var/cache/tools/Linux-aarch64/`): the official StyLua release
binary, and the luacheck 1.2.0 Lua sources run under `nvim -l` with a tiny
`vim.uv` stand-in for the `lfs` C module. Use with
`make ci TOOLDIR=.claude-data/var/cache/tools/Linux-aarch64`. The host uses
`make tools` (cargo and luarocks into `.tools/<uname -sm>/`) or MacPorts.

Decisions: `tools/check-banned` also bans `vim.fn.system` and `.spawn(` (same
"no external processes" rule); `load`/`loadstring` match only as bare calls;
any `require` whose module does not start with `doc_preview` fails, comments
included (strict, simple). Gates cover `lua/ tests/ plugin/` for stylua and
luacheck; size and banned cover `lua/` (banned also `plugin/`). luacheck uses
`std = "lua51"` (LuaJIT), tests add the busted std.

## Tasks

- [x] 1. `stylua.toml` and `.luacheckrc` (std lua51, `vim` global, busted std
   for `tests/`, complexity 10, line length left to stylua). `.gitignore`
   gets `.tools/`. Done when: both tools accept the files and report on
   `lua/ tests/ plugin/`.
- [x] 2. `tools/check-size` (POSIX sh, `MAX` default 400) and
   `tools/check-banned` (POSIX sh, grep -E, directories as arguments,
   `file:line:text` per hit, exit 1). Done when: both exit 0 on `lua/` and
   `plugin/`, and 1 on a planted violation.
- [x] 3. `tests/unit/gates_spec.lua`: each banned API and a foreign `require`
   are caught in a temp file, clean code (incl. `vim.g.loaded_x`, `x.load(`,
   `require "doc_preview.x"`) passes, size limit boundary, repo code passes.
   Done when: `agent-test` passes.
- [x] 4. Makefile targets `format`, `format-check`, `lint`, `size`, `banned`,
   `ci`, `tools`; `TOOLDIR` per platform (`.tools/$(uname -sm)`), prepended to
   `PATH`; missing tool prints a one-line install hint; `make tools`
   installs stylua (cargo `--root`) and luacheck (luarocks `--tree`) into
   it. POSIX sh, GNU/BSD make compatible. Done when: `make ci` passes, and
   `make lint` without luacheck fails with the hint.
- [x] 5. Fix existing code: `stylua` over `lua/ tests/ plugin/` (formatting
   only); luacheck findings: split `translate` in `core/out.lua` and
   `run_suite` in `tests/pairs/runner.lua` (complexity), drop the unused
   variable in `out.lua`. No behaviour change. Done when: `make ci` exits 0
   and the full test run is green.
- [x] 6. Docs: `doc/testing.md` 5 ("planned" to implemented, banned list as
   built) and 7 (`make tools`, `TOOLDIR`), `README.md` (new targets),
   `doc/plan.md` status.
- [x] 7. Host check (macOS): `make tools` (or `port install luacheck
   stylua`), then `make ci`. Verify the real `luacheck` binary agrees with
   the sandbox run (0 warnings) and `stylua --check` is clean with the host
   stylua version (formatting was done with stylua 2.6.0; a different
   version may reformat). (verified on host 2026-11-15)

Out of scope: `make docs-check` (`doc/testing.md` 6), LuaLS, `make sast`.
