-- Test-only init: repo root and plenary on the runtimepath, no user config.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(root .. "/deps/plenary.nvim")
vim.opt.swapfile = false
vim.opt.shadafile = "NONE" -- parallel test nvims must not share (and corrupt) the user ShaDa file
vim.cmd("runtime plugin/plenary.vim")
-- Test helpers (tests/pairs/*.lua) are required as "pairs.<name>".
package.path = root .. "/tests/?.lua;" .. package.path
