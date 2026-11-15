# nvim-doc-preview

Neovim plugin (Lua namespace `doc_preview`, command `:DocPreview`): previews Markdown/RST (with Mermaid) in a read-only split.

## Rules

- Lua only, Neovim 0.10+. **Zero runtime dependencies** and no external processes. Test tooling may use dependencies (plenary.nvim, fetched into gitignored `deps/`).
- Rendering is always async and cancellable.
- Follow the dependency and layout rules in `doc/architecture.md`; don't invent new layers.
- Work in vertical slices (parser, model, renderer, tests), one at a time. Every feature needs tests.
- Keep code simple and trivial: small functions, no clever abstractions.
- MIT licence: port code only from MIT-compatible sources and credit them (policy: "Porting policy and credit" in `doc/testing.md`).
- Automation lives in the `Makefile` (`agent-test` runs it); keep it POSIX sh and GNU/BSD make compatible (Linux and macOS).
- Dev tools: prefer within-repo installs (venv, per-platform `--root`/`--tree` dirs) over global ones; on the macOS host use MacPorts, not Homebrew (see "Installing dev tools" in `doc/testing.md`).
- Quality gates (stylua, luacheck, size, banned APIs): see "Static analysis and quality gates" in `doc/testing.md`.
- User-visible change: update `README.md`, `doc/doc_preview.txt` (help) and `[Unreleased]` in `CHANGELOG.md`.
- Release: `make bump V=X.Y.Z` (semver; sets `M.version`, rolls the changelog), review, commit, tag `vX.Y.Z` and move the floating major tag (`v0`) to it (`git tag -f v0`; pushing it needs `git push -f`).

## Docs (read the relevant one before working)

- `doc/architecture.md`: decisions, layout, pipeline, session/sync, config
- `doc/document-model.md`: shared `document.model` tree (md and rst)
- `doc/diagram-model.md`: Mermaid and other diagram engines
- `doc/testing.md`: test strategy, reference pairs, porting policy, quality gates
- `doc/plan.md`: delivery order, roadmap, per-component workflow
- `doc/references.md`: sources and licences of ported code and test data
- `issue/`: one unnumbered file per slice (`<name>.md`); work from the next planned one
