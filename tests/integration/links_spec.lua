local doc_preview = require("doc_preview")

vim.cmd("runtime plugin/doc_preview.lua")

local function marks(s)
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(s.prev_buf, s.ns, 0, -1, { details = true })) do
    out[#out + 1] = { row = m[2], col = m[3], end_col = m[4].end_col, group = m[4].hl_group }
  end
  return out
end

describe("DocPreview links", function()
  after_each(function()
    pcall(vim.cmd, "only")
  end)

  it("shows text with [n] markers and the Links section", function()
    vim.cmd("enew")
    local src = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(src, 0, -1, false, { "a [b][r] c", "", "[r]: /target" })
    vim.cmd("DocPreview open")
    local s = doc_preview.session(src)
    assert.is_true(doc_preview.wait(s, 2000))
    assert.same(
      { "a b[1] c", "", "Links", "[1] /target" },
      vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false)
    )
    local groups = {}
    for _, m in ipairs(marks(s)) do
      groups[#groups + 1] = m.group
    end
    table.sort(groups)
    assert.same(
      { "DocPreviewH2", "DocPreviewLink", "DocPreviewLinkMark", "DocPreviewLinkMark" },
      groups
    )
    doc_preview.close()
  end)

  it("maps the Links entry to the source line of the first use", function()
    vim.cmd("enew")
    local src = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(src, 0, -1, false, { "x", "", "[b](/u)" })
    vim.cmd("DocPreview open")
    local s = doc_preview.session(src)
    assert.is_true(doc_preview.wait(s, 2000))
    assert.equals(3, s.output:out_to_src(6))
    doc_preview.close()
  end)
end)
