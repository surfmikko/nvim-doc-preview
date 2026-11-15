local doc_preview = require("doc_preview")
local session = require("doc_preview.session")
local text = require("doc_preview.core.text")

vim.cmd("runtime plugin/doc_preview.lua")

local long = "<span " .. string.rep("abcdefghij", 12) .. ">"

local src_lines = {
  "before", -- 1
  "", -- 2
  "<div>", -- 3
  "first html line", -- 4
  long, -- 5
  "last html line", -- 6
  "</div>", -- 7
  "", -- 8
  "inline <b>tag</b> here", -- 9
  "", -- 10
  "> <pre>", -- 11
  "> quoted html", -- 12
  "> </pre>", -- 13
  "", -- 14
  "- item", -- 15
  "  <!-- listed html", -- 16
  "  -->", -- 17
}

describe("DocPreview html blocks", function()
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

  it("renders html verbatim within the window width", function()
    local s = open()
    local width = session.width(s)
    local lines = prev_lines(s)
    for _, l in ipairs(lines) do
      assert.is_true(text.width(l) <= width, l)
    end
    assert.is_truthy(find(lines, "<div>"))
    assert.is_truthy(find(lines, "first html line"))
    assert.is_truthy(find(lines, "inline <b>tag</b> here"))
    assert.is_truthy(find(lines, "quoted html"))
    assert.is_truthy(find(lines, "<!-- listed html"))
    doc_preview.close()
  end)

  it("marks html with DocPreviewHtml extmarks", function()
    local s = open()
    local ns = vim.api.nvim_get_namespaces()
    local groups = {}
    for _, id in pairs(ns) do
      local marks = vim.api.nvim_buf_get_extmarks(s.prev_buf, id, 0, -1, { details = true })
      for _, m in ipairs(marks) do
        groups[m[2] + 1] = groups[m[2] + 1] or {}
        groups[m[2] + 1][m[4].hl_group or ""] = true
      end
    end
    local lines = prev_lines(s)
    for _, pat in ipairs({ "first html line", "<b>tag</b>", "quoted html", "<!-- listed html" }) do
      local row = find(lines, pat)
      assert.is_truthy(groups[row] and groups[row].DocPreviewHtml, pat)
    end
    doc_preview.close()
  end)

  it("maps source lines in an html block 1:1 to preview rows", function()
    local s = open()
    local lines = prev_lines(s)
    assert.equals(find(lines, "first html line"), to_preview(s, 4))
    assert.equals(find(lines, "last html line"), to_preview(s, 6))
    assert.is_true(to_preview(s, 6) > to_preview(s, 5))
    assert.equals(find(lines, "quoted html"), to_preview(s, 12))
    assert.equals(find(lines, "<!-- listed html"), to_preview(s, 16))
    doc_preview.close()
  end)

  it("maps preview rows back to their source line, wrapped rows share it", function()
    local s = open()
    local lines = prev_lines(s)
    assert.equals(4, to_source(s, find(lines, "first html line")))
    assert.equals(6, to_source(s, find(lines, "last html line")))
    assert.equals(12, to_source(s, find(lines, "quoted html")))
    local first = find(lines, "<span ")
    local last = find(lines, "last html line") - 1
    assert.is_true(last > first)
    for row = first, last do
      assert.equals(5, to_source(s, row))
    end
    doc_preview.close()
  end)
end)
