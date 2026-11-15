-- Clean-config init for the demo recording (tools/demo/demo.tape).
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
vim.opt.runtimepath:prepend(root)
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.number = true
vim.cmd("runtime plugin/doc_preview.lua")
