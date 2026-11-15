local doc_preview = require("doc_preview")
local session = require("doc_preview.session")
local text = require("doc_preview.core.text")

vim.cmd("runtime plugin/doc_preview.lua")

local long = string.rep("lorem ipsum dolor sit amet ", 8)

-- 1 "before", 2 "", 3 "- top", 4 "  - nested <long>", 5 "lazy tail", 6 "  - [x] done",
-- 7 "", 8 "after"
local src_lines = {
  "before",
  "",
  "- top",
  "  - nested " .. long,
  "lazy tail",
  "  - [x] done",
  "",
  "after",
}

describe("DocPreview lists", function()
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

  local function find(lines, pattern)
    for i, l in ipairs(lines) do
      if l:find(pattern, 1, true) then
        return i
      end
    end
  end

  local function to_preview(s, row)
    vim.api.nvim_win_set_cursor(s.src_win, { row, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.src_buf })
    return vim.api.nvim_win_get_cursor(s.prev_win)[1]
  end

  it("renders nested and task lists within the window width", function()
    local s = open()
    local width = session.width(s)
    local lines = prev_lines(s)
    for _, l in ipairs(lines) do
      assert.is_true(text.width(l) <= width, l)
    end
    assert.is_truthy(find(lines, "• top"))
    assert.is_truthy(find(lines, "◦ nested"))
    assert.is_truthy(find(lines, "[x] done"))
    doc_preview.close()
  end)

  it("maps source lines in a nested item, lazy line included, to its rows", function()
    local s = open()
    local lines = prev_lines(s)
    local first = find(lines, "◦ nested")
    local last = find(lines, "[x] done") - 1
    local row4 = to_preview(s, 4)
    local row5 = to_preview(s, 5)
    assert.is_true(row4 >= first and row4 <= last)
    assert.is_true(row5 >= first and row5 <= last)
    assert.equals(find(lines, "[x] done"), to_preview(s, 6))
    doc_preview.close()
  end)

  it("maps a preview row in the nested item back to its source lines", function()
    local s = open()
    local lines = prev_lines(s)
    local row = find(lines, "◦ nested")
    vim.api.nvim_set_current_win(s.prev_win)
    vim.api.nvim_win_set_cursor(s.prev_win, { row, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.prev_buf })
    local src_row = vim.api.nvim_win_get_cursor(s.src_win)[1]
    assert.is_true(src_row >= 4 and src_row <= 5)
    doc_preview.close()
  end)
end)
