local doc_preview = require("doc_preview")

vim.cmd("runtime plugin/doc_preview.lua")

local function marks(s)
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(s.prev_buf, s.ns, 0, -1, { details = true })) do
    out[#out + 1] = { row = m[2], group = m[4].hl_group }
  end
  return out
end

describe("DocPreview headings", function()
  after_each(function()
    pcall(vim.cmd, "only")
  end)

  it("highlights headings, replaces them on edit and cleans up on close", function()
    vim.cmd("enew")
    local src = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(src, 0, -1, false, { "# a", "", "## b" })
    vim.cmd("DocPreview open")
    local s = doc_preview.session(src)
    assert.is_true(doc_preview.wait(s, 2000))
    assert.same(
      { { row = 0, group = "DocPreviewH1" }, { row = 2, group = "DocPreviewH2" } },
      marks(s)
    )

    vim.api.nvim_buf_set_lines(src, 0, -1, false, { "plain", "", "### c" })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = src })
    assert.is_true(vim.wait(2000, function()
      return vim.api.nvim_buf_get_lines(s.prev_buf, 0, 1, false)[1] == "plain"
    end))
    assert.is_true(doc_preview.wait(s, 2000))
    assert.same({ { row = 2, group = "DocPreviewH3" } }, marks(s))

    local prev_buf, ns = s.prev_buf, s.ns
    doc_preview.close()
    assert.is_false(vim.api.nvim_buf_is_valid(prev_buf))
    assert.same({}, vim.api.nvim_buf_get_extmarks(src, ns, 0, -1, {}))
  end)
end)
