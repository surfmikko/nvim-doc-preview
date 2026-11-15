local doc_preview = require("doc_preview")
local session = require("doc_preview.session")
local text = require("doc_preview.core.text")

vim.cmd("runtime plugin/doc_preview.lua")

local long = string.rep("abcdefghij", 12)

local src_lines = {
  "before", -- 1
  "", -- 2
  "```lua", -- 3
  "local a = 1", -- 4
  "local b = '" .. long .. "'", -- 5
  "local c = 3", -- 6
  "```", -- 7
  "", -- 8
  "    indented block", -- 9
  "", -- 10
  "> ```", -- 11
  "> quoted fence", -- 12
  "> ```", -- 13
  "", -- 14
  "- item", -- 15
  "", -- 16
  "  ```", -- 17
  "  listed fence", -- 18
  "  ```", -- 19
}

describe("DocPreview code blocks", function()
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

  local function to_source(s, row)
    vim.api.nvim_set_current_win(s.prev_win)
    vim.api.nvim_win_set_cursor(s.prev_win, { row, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.prev_buf })
    return vim.api.nvim_win_get_cursor(s.src_win)[1]
  end

  it("renders every code block within the window width", function()
    local s = open()
    local width = session.width(s)
    local lines = prev_lines(s)
    for _, l in ipairs(lines) do
      assert.is_true(text.width(l) <= width, l)
    end
    assert.is_truthy(find(lines, "local a = 1"))
    assert.is_truthy(find(lines, "indented block"))
    assert.is_truthy(find(lines, "quoted fence"))
    assert.is_truthy(find(lines, "listed fence"))
    assert.is_nil(find(lines, "```"))
    doc_preview.close()
  end)

  it("maps source lines in a code block 1:1 to preview rows", function()
    local s = open()
    local lines = prev_lines(s)
    local a = find(lines, "local a = 1")
    assert.equals(a, to_preview(s, 4))
    assert.equals(find(lines, "local c = 3"), to_preview(s, 6))
    assert.is_true(to_preview(s, 6) > to_preview(s, 5))
    assert.equals(find(lines, "indented block"), to_preview(s, 9))
    assert.equals(find(lines, "quoted fence"), to_preview(s, 12))
    assert.equals(find(lines, "listed fence"), to_preview(s, 18))
    doc_preview.close()
  end)

  it("maps a preview row back to its source line", function()
    local s = open()
    local lines = prev_lines(s)
    assert.equals(4, to_source(s, find(lines, "local a = 1")))
    assert.equals(6, to_source(s, find(lines, "local c = 3")))
    assert.equals(9, to_source(s, find(lines, "indented block")))
    assert.equals(12, to_source(s, find(lines, "quoted fence")))
    assert.equals(18, to_source(s, find(lines, "listed fence")))
    doc_preview.close()
  end)

  it("maps every row of a wrapped long code line to its one source line", function()
    local s = open()
    local lines = prev_lines(s)
    local first = find(lines, "local b = '")
    local last = find(lines, "local c = 3") - 1
    assert.is_true(last > first)
    for row = first, last do
      assert.equals(5, to_source(s, row))
    end
    doc_preview.close()
  end)
end)
