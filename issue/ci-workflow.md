# CI workflow (unnumbered)

Status: done

Goal: every push to `main` and every pull request runs `make ci` on Neovim
0.10.x, stable and nightly, on Linux and macOS.

Touches: `.github/workflows/ci.yml`, `doc/plan.md` (Cross-cutting list).

Out of scope: release packaging, LuaRocks publishing, `make demo` tools
(vhs, ttyd, ffmpeg), cmark oracles (pair tests use stored baselines only).

## Tasks

- [x] 1. Write `.github/workflows/ci.yml`: matrix {ubuntu, macOS} x {v0.10.4,
  stable, nightly}, pinned actions, stylua and luacheck installed into the
  Makefile's `TOOLDIR` layout and cached, then `make ci`.
- [x] 2. Mark the item in `doc/plan.md` as written, awaiting first run.
- [x] 3. Host check: push a branch, open a PR, watch the first run. Confirm:
  action tags resolve (`rhysd/action-setup-vim@v1`,
  `leafo/gh-actions-lua@v13`, `leafo/gh-actions-luarocks@v6`,
  `actions/cache@v5`); stylua 0.20.0 and luacheck 1.2.0 install on both
  OSes and match local formatting (`stylua --check` agrees with the version
  used locally, bump `STYLUA_VERSION` if not); all six jobs go green, or
  record per-version failures (nightly may be allowed to fail). Then replace
  tags with commit SHAs if wanted and move the outcome to `doc/plan.md`. (verified on host 2026-11-15)
