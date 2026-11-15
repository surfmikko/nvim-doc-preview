# nvim-doc-preview

[![ci](https://github.com/surfmikko/nvim-doc-preview/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/surfmikko/nvim-doc-preview/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/surfmikko/nvim-doc-preview)](https://github.com/surfmikko/nvim-doc-preview/releases)
[![license](https://img.shields.io/github/license/surfmikko/nvim-doc-preview)](https://github.com/surfmikko/nvim-doc-preview/blob/main/LICENSE)

Previews Markdown documents (RST is planned), with Mermaid diagrams, in a
read-only Neovim split. Rendering is asynchronous and the plugin has no runtime
dependencies.

![Demo of nvim-doc-preview](doc/demo.gif)

## Features

- [90%] **Markdown:** headings, emphasis, links, quotes, lists, code, tables, footnotes
- [80%] **Mermaid:** flowchart, sequence, class, state, ER, pie, gantt; `.mmd` files
- [90%] **Preview:** async re-render, resize, cursor/scroll sync, split or replace layouts
- [todo] **Code highlighting:** Treesitter in code blocks
- [todo] **reStructuredText:** sections, inline markup, lists, tables, directives
- [todo] **More diagram engines:** PlantUML, Graphviz dot, D2
- [todo] **Incremental block cache:** faster re-renders

## Installation

Requires Neovim 0.10+. No other dependencies.

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "surfmikko/nvim-doc-preview",
  tag = "v0", -- latest 0.x release; or pin "v0.1.0"
  cmd = "DocPreview",
  keys = { { "<leader>p", "<cmd>DocPreview toggle replace<cr>" } },
  opts = {},
}
```

Native install, no plugin manager (Neovim packages):

```sh
git clone --branch v0 https://github.com/surfmikko/nvim-doc-preview \
  ~/.local/share/nvim/site/pack/plugins/start/nvim-doc-preview
```

The plugin works without `setup()`; call it only to change the defaults.

Versions: `v0` always points to the latest 0.x release. The plugin is in
beta and 0.x releases may break; pin an exact `v0.x.x` tag for stability.

## Concepts

- **Preview:** a read-only rendering of the current buffer, re-rendered on
  edits and wrapped to the window width.
- **Sync:** cursor and scroll positions follow each other between source and
  preview.
- **Diagrams:** Mermaid blocks (and `.mmd` / `.mermaid` files) are drawn as
  text. Unsupported diagrams show the source in a box.
- **Layout:** the preview opens as a vertical or horizontal split, or
  replaces the source in the current window.

## Usage

Commands:

- `:DocPreview` toggles the preview (same as `:DocPreview toggle`).
- `:DocPreview open [layout]` opens the preview.
- `:DocPreview close` closes the preview.
- `:DocPreview toggle [layout]` closes the preview if open, otherwise opens it.
- `:DocPreview sync on` turns cursor and scroll sync on.
- `:DocPreview sync off` turns it off.

`layout` is `vsplit`, `hsplit` or `replace`; it overrides the `layout` option
for that preview. Without it, the configured layout is used.

`q` in the preview closes it.

Help: `:help doc_preview`. Diagnostics: `:checkhealth doc_preview`.

Example mapping:

```lua
vim.keymap.set("n", "<leader>p", "<cmd>DocPreview toggle replace<cr>")
```

## Configuration

```lua
require("doc_preview").setup({
  debounce_ms = 150,
  large_file_lines = 5000,
  max_width = 100,
  layout = "vsplit",   -- vsplit | hsplit | replace
  charset = "unicode", -- unicode | ascii
  sync = { cursor = true, scroll = true },
  keymaps = { close = "q" }, -- lhs or false; keymaps = false for none
})
```

## Development

Requires Neovim 0.10+, git and make. Run `make test` for the test suite and
`make ci` for all checks. See `doc/testing.md`.

Demo: `make demo` records `doc/demo.gif` (needs VHS, ttyd, ffmpeg; on macOS `make ports` installs them).
On macOS, `make ports` installs vhs, ttyd, ffmpeg, cmark and cmark-gfm via MacPorts; then run `make tools` (as your normal user, not with sudo).

## License

MIT, see [LICENSE](LICENSE). Third-party credits are in [NOTICE](NOTICE).
