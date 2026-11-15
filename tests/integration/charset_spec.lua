local config = require("doc_preview.config")
local doc_preview = require("doc_preview")
local text = require("doc_preview.core.text")

vim.cmd("runtime plugin/doc_preview.lua")

describe("DocPreview charset", function()
  after_each(function()
    pcall(vim.cmd, "only")
    config.setup({})
  end)

  it("renders an ASCII-only preview within the width", function()
    config.setup({ charset = "ascii" })
    vim.o.columns = 40
    vim.cmd("enew")
    local src = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(src, 0, -1, false, {
      "- item",
      "  - nested",
      "",
      "---",
      "",
      "> quote",
      "",
      "| a | b |",
      "|---|---|",
      "| 1 | 2 |",
    })
    vim.cmd("DocPreview open")
    local s = doc_preview.session(src)
    assert.is_true(doc_preview.wait(s, 2000))
    local lines = vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false)
    assert.is_true(#lines > 0)
    for _, line in ipairs(lines) do
      assert.is_nil(line:find("[\128-\255]"), line)
      assert.is_true(text.width(line) <= 40)
    end
    doc_preview.close()
  end)
end)
