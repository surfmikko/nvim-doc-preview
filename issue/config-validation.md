# 0018 Config and validation

Status: done

Goal: `setup()` validates options with an error naming the key and the
allowed values; config key `split` becomes `layout`; keymaps, charset and
other documented keys exist.

Touches: `config.lua` (validate; `split` to `layout`; `keymaps`, `charset`,
`sync`, `engines`, `mermaid`, large-file threshold key if taken here),
`session.lua` (layout to window options, `ctx.charset` plumbed into the
render ctx, keymaps used by 0008), `init.lua` (`setup` error reporting),
`plugin/doc_preview.lua` (`nargs` from 1 to `?` where needed, completion),
`document/render.lua`/`core` readers of `ctx.charset`,
`tests/unit/config_spec.lua` (new), integration.

Brings: `doc/architecture.md` 8 as code; breaking rename `split` to
`layout` (nothing shipped yet, document it in the commit message);
validation rule of 5.1.1 for the names `vsplit|hsplit|replace`. The
`replace` behaviour itself is 0020: here the name validates and `vsplit`
keeps working (and `hsplit`, if trivial); an unimplemented layout reports
a clear "not yet supported" error rather than silently falling back.

Tests: unit: defaults, invalid values rejected with key and allowed
values, `layout` migration; integration: configured keymap works,
`ctx.charset` ascii output for rules and tables (0009, 0014 defaulted to
unicode).

References: `doc/architecture.md` 2 ("Layout" row), 5.1.1, 5.2, 8;
`doc/testing.md` 1.1; `:h vim.validate`.

Depends on: 0008 (keymap keys), 0014 (charset readers).

Out of scope: `replace`/`hsplit` window logic and `open [layout]`
argument (0020), `:checkhealth`.

## Tasks

Decisions fixed by this plan (the coder does not re-decide them):

- Validation is table-driven (one schema entry per key: checker plus allowed-values text) so no function nears cyclomatic complexity 10. Errors read `doc_preview.setup: <key> must be <allowed>, got <value>`, with nested keys dotted (`sync.cursor`, `keymaps.close`).
- `setup()` validates the merged result before assigning `M.options`; a rejected call leaves the previous options untouched (raised with `error(msg, 0)`, no stack noise).
- Unknown top-level keys are rejected, naming the key and listing the valid ones. `split` gets its own message: `'split' was renamed to 'layout' (vsplit|hsplit|replace)`. This is the migration: a clear error, no silent translation (nothing has shipped).
- `keymaps.<name>` is a non-empty string, or `false` to leave that action unmapped.
- `layout`: `vsplit` and `hsplit` (`{ split = "right" }` / `{ split = "below" }`) work here; `replace` validates but `session.open` reports `layout 'replace' is not yet supported (issue 0020)` via `vim.notify` ERROR and opens nothing. 0020 removes that guard.
- Keys with no consumer yet (`engines`, `mermaid`, `auto_open`) are validated and stored only, marked reserved in `config.lua` and README. The large-file threshold key is owned by 0019, not added here.
- Glyph sets for the new `ctx.charset` readers go in `core/box.lua` (it already owns `glyphs(charset)`), not in `document/render.lua` (335 lines now, keep it under 400).

- [x] 1. `config.lua` and `init.lua` (`setup` error path): replace `split` with the full documented key set and defaults from `doc/architecture.md` 8 (`debounce_ms`, `slice_ms`, `max_width`, `layout = "vsplit"`, `charset = "unicode"`, `sync = { cursor = true, scroll = true }`, `engines`, `auto_open = false`, `mermaid = { enabled = true }`, `keymaps = { jump_to_source = "<CR>", close = "q" }`); add the schema-driven validator, the `split` migration error and unknown-key rejection described above. New `tests/unit/config_spec.lua`: defaults (including nested merge, e.g. partial `keymaps`), each key rejected with a message containing the key and the allowed values, `layout` accepts the three names and rejects others, `split` migration message, failed `setup` keeps previous options, `keymaps.x = false` accepted. Update any spec or README text that mentions `split`.
- [x] 2. `core/box.lua`, `document/render.lua`, `session.lua`: add the non-table glyphs to the charset sets in `box.lua` (rule `─`/`-`, quote prefix `│ `/`| `, bullets `• ◦ ▪`/`* - +`) with accessor(s) next to `glyphs`; make `thematic_break`, `blockquote` and `bullet_glyph` read `ctx.charset` and drop the "until 0018" comments and local constants; set `ctx.charset = config.options.charset` in `session.render` (table code already reads `ctx.charset`). Keep every glyph at display width equal to its unicode counterpart so wrapping math is unchanged. Tests: extend `tests/unit/box_spec.lua` for the new sets; add an ascii case to the render/document unit specs (rule, quote prefix, nested bullets, table borders) and a unicode-default case; integration (`session_spec` or new `tests/integration/config_spec.lua`): `setup({ charset = "ascii" })` renders an ASCII-only preview for a document with rule, quote, list and table, and no line exceeds the width.
- [x] 3. `session.lua`: in `open`, derive the window from `config.options.layout` (`vsplit` -> `split = "right"`, `hsplit` -> `split = "below"`, `replace` -> notify the not-yet-supported error and return nil without creating buffer, window or session; `init.open` must tolerate a nil result); make `set_keymaps` read `config.options.keymaps` (skip actions set to `false`, use the configured lhs for `jump_to_source` and `close`), still buffer-local with no leaked maps. Tests (`tests/integration/config_spec.lua`): `layout = "hsplit"` opens the preview below (window is below, same width as source), `vsplit` right; `replace` opens nothing and notifies; custom `keymaps.jump_to_source = "<leader>j"` jumps and `<CR>` is no longer mapped in the preview; `keymaps.close = false` leaves no `q` map; defaults still behave as in `cr_jump_spec`; no leaked maps after close. Reset options in `after_each` via `setup({})` so other specs are unaffected.
- [x] 4. `plugin/doc_preview.lua` and `init.lua` (`command`, `complete`): change `nargs` from `"+"` to `"*"` so a bare `:DocPreview` is valid (it runs `toggle`; `sync` still needs its argument and keeps its error); completion unchanged for existing subcommands. Do not add the `open [layout]` argument (0020). Tests: bare `:DocPreview` toggles; `open`, `close`, `sync on|off` and the unknown-subcommand error keep working (`session_spec`, `cr_jump_spec`).
- [x] 5. `sync.lua` (only if trivial; otherwise skip and say so in the task note and README): honour `sync.cursor` and `sync.scroll` from config (both false starts the session with `sync_enabled = false`; individual flags gate the matching direction in `follow` without raising `follow`'s complexity above 10, e.g. by a small `enabled_for(kind)` helper). Implemented via `enabled_for(kind)` in `sync.lua`; tests in `tests/integration/command_spec.lua` (also covers task 4). Test: `sync = { cursor = false, scroll = false }` disables mirroring until `:DocPreview sync on`.
- [x] 6. Docs: `README.md` configuration section (all keys, defaults, `layout` names with `replace` pending 0020, `keymaps`, `charset`, reserved keys, the `split` to `layout` rename); `doc/architecture.md` 2 (Layout row) and 8 only where behaviour differs from the text (`false` disables a keymap, `replace` unsupported until 0020, reserved keys); remove the "keys are hard-coded until 0018" notes from `README.md`. Set Status to done when 2-5 are verified.
- [x] 7. `agent-test --full` passes in the sandbox (all unit and integration specs, size and banned-API gates; files stay under 400 lines).
- [x] 8. (host verify; hand-checked in sandbox: complexity <= 10, files < 400 lines, formatting by eye) `make ci`: `stylua --check` and `luacheck` (cyclomatic complexity <= 10 per function) are not installable in the sandbox; run on the host and fix findings, mainly in `config.lua`'s validator and any touched `session.lua`/`render.lua` function. (verified on host 2026-11-15)

Commit message note (breaking change): config key `split` (`right|left|below|above`) is renamed to `layout` (`vsplit|hsplit|replace`); `setup({ split = ... })` now raises a clear error. Nothing was shipped before, so there is no deprecation period.
