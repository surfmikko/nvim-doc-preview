local doc_preview = require("doc_preview")
local session = require("doc_preview.session")
local text = require("doc_preview.core.text")

vim.cmd("runtime plugin/doc_preview.lua")

local long = string.rep("lorem ipsum dolor sit amet ", 12)

-- source lines: 1 "before", 2 "", 3 "> long...", 4 "lazy line", 5 "", 6 "after"
local src_lines = { "before", "", "> " .. long, "lazy line", "", "after" }

describe("DocPreview block quote", function()
  after_each(function()
    pcall(vim.cmd, "only")
  end)

  local function open()
    vim.cmd("enew")
    local src = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(src, 0, -1, false, src_lines)
    vim.cmd("DocPreview open")
    local s = doc_preview.session(src)
    assert.is_true(doc_preview.wait(s, 2000))
    vim.wait(50)
    return s
  end

  local function prev_lines(s)
    return vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false)
  end

  local function to_preview(s, row)
    vim.api.nvim_win_set_cursor(s.src_win, { row, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.src_buf })
    return vim.api.nvim_win_get_cursor(s.prev_win)[1]
  end

  it("renders quote lines within the window width", function()
    local s = open()
    local width = session.width(s)
    local lines = prev_lines(s)
    local quoted = 0
    for _, l in ipairs(lines) do
      assert.is_true(text.width(l) <= width, l)
      if vim.startswith(l, "│ ") then
        quoted = quoted + 1
      end
    end
    assert.is_true(quoted >= 2)
    doc_preview.close()
  end)

  it("maps source lines inside the quote, lazy line included, to quote rows", function()
    local s = open()
    local lines = prev_lines(s)
    local first, last
    for i, l in ipairs(lines) do
      if vim.startswith(l, "│ ") then
        first = first or i
        last = i
      end
    end
    local row3 = to_preview(s, 3)
    local row4 = to_preview(s, 4)
    assert.is_true(row3 >= first and row3 <= last)
    assert.is_true(row4 >= first and row4 <= last)
    doc_preview.close()
  end)

  it("maps a preview row in the quote back to a source line in it", function()
    local s = open()
    local lines = prev_lines(s)
    local row
    for i, l in ipairs(lines) do
      if vim.startswith(l, "│ ") then
        row = i
        break
      end
    end
    vim.api.nvim_set_current_win(s.prev_win)
    vim.api.nvim_win_set_cursor(s.prev_win, { row, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.prev_buf })
    local src_row = vim.api.nvim_win_get_cursor(s.src_win)[1]
    assert.is_true(src_row >= 3 and src_row <= 4)
    doc_preview.close()
  end)
end)
