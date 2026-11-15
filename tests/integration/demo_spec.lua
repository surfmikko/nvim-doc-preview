local doc_preview = require("doc_preview")

vim.cmd("runtime plugin/doc_preview.lua")

-- The command sequence of tools/demo/demo.tape, on the demo sample.
describe("DocPreview demo story on doc/sample-markdown-demo.md", function()
  after_each(function()
    pcall(vim.cmd, "only")
  end)

  it("toggles replace, vsplit and hsplit on and off in order", function()
    vim.o.columns = 100
    vim.o.lines = 30
    vim.cmd("edit doc/sample-markdown-demo.md")
    local src = vim.api.nvim_get_current_buf()
    local expected_wins = { replace = 1, vsplit = 2, hsplit = 2 }
    for _, layout in ipairs({ "replace", "vsplit", "hsplit" }) do
      vim.cmd("DocPreview toggle " .. layout)
      local s = doc_preview.session(src)
      assert.equals(layout, s.layout)
      assert.is_true(doc_preview.wait(s, 3000))
      assert.equals(expected_wins[layout], #vim.api.nvim_tabpage_list_wins(0))
      assert.is_true(#vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false) > 30)
      vim.cmd("normal! \4")
      vim.cmd("normal! \21")
      vim.cmd("DocPreview toggle")
      assert.is_nil(doc_preview.session(src))
      assert.equals(1, #vim.api.nvim_tabpage_list_wins(0))
    end
  end)
end)
