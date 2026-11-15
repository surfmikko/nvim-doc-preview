-- Highlight groups and span application (doc/architecture.md 7).
local M = {}

-- Defined with default = true so colour schemes can override them.
function M.setup()
  for level = 1, 6 do
    vim.api.nvim_set_hl(0, "DocPreviewH" .. level, { link = "Title", default = true })
  end
  vim.api.nvim_set_hl(0, "DocPreviewEmph", { italic = true, default = true })
  vim.api.nvim_set_hl(0, "DocPreviewStrong", { bold = true, default = true })
  vim.api.nvim_set_hl(0, "DocPreviewStrike", { strikethrough = true, default = true })
  vim.api.nvim_set_hl(0, "DocPreviewCode", { link = "String", default = true })
  vim.api.nvim_set_hl(0, "DocPreviewLink", { link = "Underlined", default = true })
  vim.api.nvim_set_hl(0, "DocPreviewLinkMark", { link = "Special", default = true })
  vim.api.nvim_set_hl(0, "DocPreviewFootnoteRef", { link = "Special", default = true })
  vim.api.nvim_set_hl(0, "DocPreviewListMarker", { link = "Special", default = true })
  vim.api.nvim_set_hl(0, "DocPreviewHtml", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "DocPreviewQuote", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "DocPreviewImage", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "DocPreviewTableHeader", { link = "Title", default = true })
  vim.api.nvim_set_hl(0, "DocPreviewTableBorder", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "DocPreviewDiagramBorder", { link = "Special", default = true })
  vim.api.nvim_set_hl(0, "DocPreviewDiagramEdge", { link = "Delimiter", default = true })
  vim.api.nvim_set_hl(0, "DocPreviewDiagramLabel", { link = "Identifier", default = true })
  vim.api.nvim_set_hl(0, "DocPreviewErrbox", { link = "Comment", default = true })
end

---@param buf integer
---@param ns integer
---@param spans table[] Output spans (line 1-based, columns 0-based, end exclusive)
function M.apply(buf, ns, spans)
  for _, s in ipairs(spans) do
    vim.api.nvim_buf_set_extmark(buf, ns, s.line - 1, s.col_start, {
      end_col = s.col_end,
      hl_group = s.hl_group,
      strict = false,
    })
  end
end

return M
