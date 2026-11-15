local config = require("doc_preview.config")
local doc_preview = require("doc_preview")
local session = require("doc_preview.session")
local text = require("doc_preview.core.text")

vim.cmd("runtime plugin/doc_preview.lua")

local src_lines = {
  "before", -- 1
  "", -- 2
  "```mermaid", -- 3
  "flowchart TD", -- 4
  "A[Start]", -- 5
  "```", -- 6
  "", -- 7
  "after", -- 8
}

describe("DocPreview mermaid block", function()
  after_each(function()
    doc_preview.close()
    config.setup({})
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

  local function find(lines, str)
    for i, l in ipairs(lines) do
      if l:find(str, 1, true) then
        return i
      end
    end
  end

  it("renders the diagram and leaves the rest of the document alone", function()
    local s = open()
    local lines = prev_lines(s)
    assert.is_truthy(find(lines, "│ Start │"))
    assert.equals("before", lines[1])
    assert.equals("after", lines[#lines])
    assert.is_nil(find(lines, "```"))
  end)

  it("maps a source line inside the block to the block and back", function()
    local s = open()
    local lines = prev_lines(s)
    local top = find(lines, "┌───────┐")
    vim.api.nvim_set_current_win(s.src_win)
    vim.api.nvim_win_set_cursor(s.src_win, { 5, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.src_buf })
    local row = vim.api.nvim_win_get_cursor(s.prev_win)[1]
    assert.is_true(row >= top and row <= top + 2)
    vim.api.nvim_set_current_win(s.prev_win)
    vim.api.nvim_win_set_cursor(s.prev_win, { top + 1, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.prev_buf })
    local src_row = vim.api.nvim_win_get_cursor(s.src_win)[1]
    assert.is_true(src_row >= 3 and src_row <= 6)
  end)

  it("never exceeds the window width and re-renders on resize", function()
    local s = open()
    vim.api.nvim_win_set_width(s.prev_win, 8)
    vim.api.nvim_exec_autocmds("VimResized", {})
    vim.wait(500, function()
      return session.width(s) == 8 and s.width == 8
    end)
    assert.is_true(doc_preview.wait(s, 2000))
    for _, l in ipairs(prev_lines(s)) do
      assert.is_true(text.width(l) <= 8, l)
    end
  end)

  it("shows plain code when engines.mermaid is false", function()
    config.setup({ engines = { mermaid = false } })
    local lines = prev_lines(open())
    assert.is_truthy(find(lines, "flowchart TD"))
    assert.is_nil(find(lines, "┌"))
  end)
end)
