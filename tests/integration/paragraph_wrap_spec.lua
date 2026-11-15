local doc_preview = require("doc_preview")
local session = require("doc_preview.session")
local text = require("doc_preview.core.text")

vim.cmd("runtime plugin/doc_preview.lua")

local long = string.rep("lorem ipsum dolor sit amet ", 20)
local cjk = string.rep("日本語のテキスト", 15)

describe("DocPreview paragraph wrapping", function()
  after_each(function()
    pcall(vim.cmd, "only")
  end)

  local function open()
    vim.cmd("enew")
    local src = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(src, 0, -1, false, { long, "", cjk })
    vim.cmd("DocPreview open")
    local s = doc_preview.session(src)
    assert.is_true(doc_preview.wait(s, 2000))
    vim.wait(50)
    return s
  end

  it("wraps to the window width", function()
    local s = open()
    local width = session.width(s)
    local lines = vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false)
    assert.is_true(#lines > 3)
    for _, l in ipairs(lines) do
      assert.is_true(text.width(l) <= width, l)
    end
    doc_preview.close()
  end)

  it("keeps the preview cursor inside the wrapped range", function()
    local s = open()
    local n = #vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false)
    local first_end
    for i, l in ipairs(vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false)) do
      if l == "" then
        first_end = i - 1
        break
      end
    end
    assert.is_true(first_end > 1)
    vim.api.nvim_win_set_cursor(s.src_win, { 1, 40 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.src_buf })
    local row = vim.api.nvim_win_get_cursor(s.prev_win)[1]
    assert.is_true(row >= 1 and row <= first_end and row <= n)
    doc_preview.close()
  end)
end)
