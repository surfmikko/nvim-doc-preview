if vim.g.loaded_doc_preview then
  return
end
vim.g.loaded_doc_preview = true

vim.api.nvim_create_user_command("DocPreview", function(opts)
  require("doc_preview").command(opts.args)
end, {
  nargs = "*",
  complete = function(lead, line)
    return require("doc_preview").complete(lead, line)
  end,
})
