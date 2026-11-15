local doc_preview = require("doc_preview")

vim.cmd("runtime plugin/doc_preview.lua")

local function marks(s)
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(s.prev_buf, s.ns, 0, -1, { details = true })) do
    out[#out + 1] = { row = m[2], col = m[3], end_col = m[4].end_col, group = m[4].hl_group }
  end
  return out
end

describe("DocPreview inline styles", function()
  after_each(function()
    pcall(vim.cmd, "only")
  end)

  it("removes markers and highlights styled text in the preview", function()
    vim.cmd("enew")
    local src = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(src, 0, -1, false, { "a *b* **c** `d`" })
    vim.cmd("DocPreview open")
    local s = doc_preview.session(src)
    assert.is_true(doc_preview.wait(s, 2000))
    assert.same({ "a b c d" }, vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false))
    assert.same({
      { row = 0, col = 2, end_col = 3, group = "DocPreviewEmph" },
      { row = 0, col = 4, end_col = 5, group = "DocPreviewStrong" },
      { row = 0, col = 6, end_col = 7, group = "DocPreviewCode" },
    }, marks(s))
    doc_preview.close()
  end)
end)
