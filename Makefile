# POSIX sh + GNU/BSD make compatible (Linux, macOS). No build output.

NVIM ?= nvim
PLENARY := deps/plenary.nvim
PLENARY_REV := 74b06c6c75e4eeb3108ec01852001636d85a932b
# Per-platform dev tool dir (stylua, luacheck); gitignored, never shared between
# host and sandbox. Override: make ci TOOLDIR=<dir>. Install: make tools.
TOOLDIR ?= .tools/$(shell uname -sm | tr ' ' '-')
export PATH := $(CURDIR)/$(TOOLDIR)/bin:$(PATH)
# Global macOS tools that cannot be installed in-repo (make ports; MacPorts).
PORTS ?= vhs ttyd ffmpeg cmark cmark-gfm
LUA_DIRS := lua tests plugin
RUN := $(NVIM) --headless --noplugin -u tests/minimal_init.lua -c

.PHONY: help deps test test-unit test-integration test-golden test-pairs run run-sample clean \
	tools ports format format-check lint size banned ci demo bump

help:
	@echo "targets: deps test test-unit test-integration test-golden test-pairs"
	@echo "         tools ports format format-check lint size banned ci run run-sample demo bump clean"


### Development tools and dependencies

deps: $(PLENARY)

$(PLENARY):
	git init -q $(PLENARY)
	git -C $(PLENARY) fetch -q --depth 1 https://github.com/nvim-lua/plenary.nvim $(PLENARY_REV)
	git -C $(PLENARY) checkout -q FETCH_HEAD

tools:
	cargo install stylua --root $(TOOLDIR)
	luarocks --tree $(TOOLDIR) install luacheck

ports:
	sudo port install $(PORTS)

### Release

# make bump V=X.Y.Z: set M.version, roll CHANGELOG.md; does not commit or tag.
bump:
	@test -n "$(V)" || { echo "usage: make bump V=X.Y.Z"; exit 2; }
	@tools/bump $(V)

### Tests runners

ci: format-check lint size banned test

test: test-unit test-integration test-golden test-pairs

test-unit: deps
	$(RUN) "PlenaryBustedDirectory tests/unit {minimal_init = 'tests/minimal_init.lua'}"

test-golden: deps
	$(RUN) "PlenaryBustedDirectory tests/golden {minimal_init = 'tests/minimal_init.lua'}"

test-pairs: deps
	$(RUN) "PlenaryBustedDirectory tests/pairs {minimal_init = 'tests/minimal_init.lua'}"

test-integration: deps
	$(RUN) "PlenaryBustedDirectory tests/integration {minimal_init = 'tests/minimal_init.lua'}"

format:
	stylua $(LUA_DIRS)

format-check:
	stylua --check $(LUA_DIRS)

lint:
	luacheck $(LUA_DIRS)

size:
	sh tools/check-size lua

banned:
	sh tools/check-banned lua plugin

### Manual testing and helpers

FILE ?= doc/architecture.md

run:
	$(NVIM) --cmd 'set rtp^=$(CURDIR)' $(FILE) \
		-c 'nnoremap <leader>p <cmd>DocPreview toggle hsplit<cr>' -c 'DocPreview open'

run-sample:
	$(MAKE) run FILE=doc/markdown-sample.md

demo:
	vhs tools/demo/demo.tape

clean:
	rm -rf deps
