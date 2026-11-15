# Demo GIF

Goal: a reproducible GIF demo, recorded on the macOS host with VHS
(`make demo` writes `doc/demo.gif`).

## Tasks

- [x] `doc/sample-markdown-demo.md`: short sample (headings, emphasis, link, list, table, lua block, flowchart, sequence diagram); rendered headless at 100 and 50 columns, no errors, no box fallback.
- [x] `tools/demo/init.lua` (clean config, repo on rtp) and `tools/demo/demo.tape` (replace, vsplit, hsplit story).
- [x] `make demo`: checks vhs/ttyd/ffmpeg, prints a MacPorts hint, runs the tape (missing-tool path verified here).
- [x] README Development line; the image link is not added until the GIF exists.
- [x] `tests/integration/demo_spec.lua`: the tape's `:DocPreview` sequence on the sample.
- [x] `make tools` installs stylua, luacheck and vhs (`go install`) into `.tools/<uname -sm>`, inline in the Makefile (no setup scripts); `make deps` is plenary only.
- [x] `make ports` (`PORTS ?= vhs ttyd ffmpeg cmark cmark-gfm`, MacPorts, one sudo call for missing ports) and a root guard in `make tools`; `make demo` comment, README, `doc/testing.md` updated. Verified in the sandbox with fake `uname`/`port`/`sudo`/`id` shims.
- [x] Host (macOS): vhs v0.12.1 installed from MacPorts and `make demo` recorded the GIF. `make tools` no longer installs vhs; `make ports` does (unpinned).
- [x] Host: `make demo` ran and `doc/demo.gif` checked.
  - `port search vhs ttyd ffmpeg`; install per the hint in `make demo` (port names unverified), or per the VHS README.
  - Check the tape syntax is accepted (`Set Padding`, `Set Theme "Dracula"`, `Ctrl+D`, `Set Shell`) and the window shows ~100x30 cells; tune `Width`/`Height`/`FontSize`.
  - Check timing: Sleeps long enough for render, Ctrl-D/U scrolls visibly, GIF is short.
  - Then add `![demo](doc/demo.gif)` under the README intro and close this issue.
