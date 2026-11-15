local doc_preview = require("doc_preview")

vim.cmd("runtime plugin/doc_preview.lua")

local src_lines = {
  "Intro", -- 1
  "", -- 2
  "A claim[^a] here.", -- 3
  "", -- 4
  "[^a]: A long footnote text that has to wrap over several rows of the preview window.", -- 5
  "", -- 6
  "After", -- 7
}

describe("DocPreview footnotes", function()
  after_each(function()
    pcall(vim.cmd, "only")
  end)

  local function open(width)
    vim.o.columns = width or 40
    vim.cmd("enew")
    local src = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(src, 0, -1, false, src_lines)
    vim.cmd("DocPreview open")
    local s = doc_preview.session(src)
    assert.is_true(doc_preview.wait(s, 2000))
    vim.wait(50)
    return s
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

  it("renders markers with extmarks and a Footnotes section within the width", function()
    local s = open(40)
    local lines = vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false)
    assert.is_truthy(find(lines, "A claim[^1] here."))
    assert.is_truthy(find(lines, "Footnotes"))
    local width = vim.api.nvim_win_get_width(s.prev_win)
    for _, l in ipairs(lines) do
      assert.is_true(vim.fn.strdisplaywidth(l) <= width, l)
    end
    local rows = {}
    for _, id in pairs(vim.api.nvim_get_namespaces()) do
      for _, m in ipairs(vim.api.nvim_buf_get_extmarks(s.prev_buf, id, 0, -1, { details = true })) do
        if m[4].hl_group == "DocPreviewFootnoteRef" then
          rows[m[2] + 1] = true
        end
      end
    end
    assert.is_true(rows[find(lines, "A claim")])
    doc_preview.close()
  end)

  it("maps the reference line and the definition range to rows and back", function()
    local s = open(40)
    local lines = vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false)
    local claim = find(lines, "A claim")
    local first = find(lines, "1. A long footnote")
    local last = find(lines, "preview window.")
    assert.is_true(last > first)
    assert.equals(claim, to_preview(s, 3))
    -- the section title row maps to the first definition's start line
    assert.equals(find(lines, "Footnotes"), to_preview(s, 5))
    assert.equals(5, to_source(s, find(lines, "Footnotes")))
    assert.equals(3, to_source(s, claim))
    for row = first, last do
      assert.equals(5, to_source(s, row))
    end
    doc_preview.close()
  end)
end)
