# Review cleanup: docs, config, repo hygiene
Status:       done
Goal:         Remove misleading docs and dead or no-op options found in the project review, and tidy the repo root.
Touches:      `README.md`, `.gitignore`, repo root files, `lua/doc_preview/config.lua` (+ its unit spec), `lua/doc_preview/core/highlight.lua`, `Makefile`, `lua/doc_preview/mermaid/gantt_draw.lua`
Source:       project review findings 3-6, 8, 9, report `.claude-data/var/report/reviewer-project-20261115-1201.md`
Parallel:     no overlap with the other review issues. Tasks inside it are independent of each other.

## Tasks

- [x] 1. `README.md:3`: reword "Previews Markdown and RST" to Markdown, RST planned (no `rst/` exists).
- [x] 2. Repo root: delete `ci.log`, `log`, `test`, `test.log`, `pairs.log`, `table.png` (or move useful ones to `.claude-data/var/log/`); add `*.log` and `/log`, `/test`, `/table.png` style entries to `.gitignore`. Check `Makefile` does not write these to the root; redirect if it does.
- [x] 3. `config.lua:10-16`: decide for `mermaid.enabled`, `engines.dot/plantuml/d2`, `auto_open`: wire `mermaid.enabled` or drop it (`engines.mermaid` already switches the engine); reject or warn on keys still reserved. Update the config unit tests, `doc/architecture.md` config block (~line 526) and README options if they change.
- [x] 4. `core/highlight.lua:8,22`: `hlexists("Title")` is always 1; link `DocPreviewH1..6` and `DocPreviewTableHeader` to `Title` directly and drop the dead `markdownH*`/`Special` fallbacks. Existing highlight tests must pass.
- [x] 5. vhs: decided against pinning. It is dev-only (demo GIF), so `make ports` installs the latest MacPorts `vhs` and `make tools` no longer builds it.
- [x] 6. `mermaid/gantt_draw.lua`: the unused-argument warning no longer reproduces in the current source (stale `ci.log`). Host verify: `make lint` clean. (verified on host 2026-11-15)

Done when: `agent-test` green; host `make ci` clean.
