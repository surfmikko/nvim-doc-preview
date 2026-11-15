local doc_preview = require("doc_preview")
local session = require("doc_preview.session")
local text = require("doc_preview.core.text")

vim.cmd("runtime plugin/doc_preview.lua")

local src_lines = {
  "before", -- 1
  "", -- 2
  "| Name | Description |", -- 3
  "|:-----|------------:|", -- 4
  "| a | short |", -- 5
  "| b | a much longer description that has to wrap inside its cell when narrow |", -- 6
  "| c | last |", -- 7
  "", -- 8
  "after", -- 9
}

describe("DocPreview tables", function()
  after_each(function()
    pcall(vim.cmd, "only")
  end)

  local function open(columns)
    vim.o.columns = columns or 80
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

  it("renders a grid with no row wider than the window", function()
    for _, columns in ipairs({ 120, 80, 50, 30, 20 }) do
      local s = open(columns)
      local lines = prev_lines(s)
      assert.is_truthy(find(lines, "┌"))
      assert.is_truthy(find(lines, "└"))
      local width = session.width(s)
      for _, l in ipairs(lines) do
        assert.is_true(text.width(l) <= width, columns .. ": " .. l)
      end
      doc_preview.close()
      pcall(vim.cmd, "only")
    end
  end)

  it("marks header and borders with extmarks", function()
    local s = open()
    local groups = {}
    for _, id in pairs(vim.api.nvim_get_namespaces()) do
      local marks = vim.api.nvim_buf_get_extmarks(s.prev_buf, id, 0, -1, { details = true })
      for _, m in ipairs(marks) do
        local g = m[4].hl_group
        groups[m[2] + 1] = groups[m[2] + 1] or {}
        if g then
          groups[m[2] + 1][g] = true
        end
      end
    end
    local lines = prev_lines(s)
    local top = find(lines, "┌")
    assert.is_true(groups[top].DocPreviewTableBorder)
    assert.is_true(groups[find(lines, "Name")].DocPreviewTableHeader)
    doc_preview.close()
  end)

  it("maps each source row to its preview row", function()
    local s = open()
    local lines = prev_lines(s)
    local top = find(lines, "┌")
    assert.is_true(to_preview(s, 3) >= top and to_preview(s, 3) <= find(lines, "Name"))
    assert.equals(find(lines, "short"), to_preview(s, 5))
    assert.equals(find(lines, "last"), to_preview(s, 7))
    assert.is_true(to_preview(s, 7) > to_preview(s, 5))
    assert.equals(find(lines, "after"), to_preview(s, 9))
    doc_preview.close()
  end)

  it("maps preview rows back, wrapped rows share the source line", function()
    local s = open(50)
    local lines = prev_lines(s)
    assert.equals(3, to_source(s, find(lines, "Name")))
    assert.equals(5, to_source(s, find(lines, "short")))
    local first = find(lines, "│ b")
    local last = find(lines, "│ c") - 1
    assert.is_true(last > first)
    for row = first, last do
      assert.equals(6, to_source(s, row))
    end
    doc_preview.close()
  end)
end)
