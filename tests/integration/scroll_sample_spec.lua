local doc_preview = require("doc_preview")
local render = require("doc_preview.document.render")

vim.cmd("runtime plugin/doc_preview.lua")

local SAMPLE = "doc/markdown-sample.md"

local function open()
  vim.o.columns = 200
  vim.cmd("edit " .. SAMPLE)
  local src = vim.api.nvim_get_current_buf()
  vim.cmd("DocPreview open")
  local s = doc_preview.session(src)
  assert.is_true(doc_preview.wait(s, 2000))
  vim.wait(50)
  vim.api.nvim_win_set_height(s.src_win, 15)
  vim.api.nvim_win_set_height(s.prev_win, 15)
  return s
end

local function headings()
  local t = {}
  for i, l in ipairs(vim.fn.readfile(SAMPLE)) do
    local text = l:match("^#+%s+(.-)%s*$")
    if text then
      t[#t + 1] = { line = i, text = text }
    end
  end
  return t
end

local function line_of(win, n)
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), n - 1, n, false)[1]
end

-- Footnote definitions render at the end of the preview, so their lines
-- legitimately map out of order.
local function footnote_lines()
  local skip, inside = {}, false
  for i, l in ipairs(vim.fn.readfile(SAMPLE)) do
    inside = l:match("^%[%^") ~= nil or (inside and l ~= "")
    skip[i] = inside
  end
  return skip
end

describe("DocPreview scroll sync on doc/markdown-sample.md", function()
  after_each(function()
    render.test_hook = nil
    pcall(vim.cmd, "only")
  end)

  it("source cursor on each heading lands on that heading in the preview", function()
    local s = open()
    local hs = headings()
    assert.is_true(#hs > 5)
    for _, h in ipairs(hs) do
      vim.api.nvim_win_set_cursor(s.src_win, { h.line, 0 })
      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.src_buf })
      local row = vim.api.nvim_win_get_cursor(s.prev_win)[1]
      assert.is_truthy(line_of(s.prev_win, row):find(h.text, 1, true), h.text)
    end
    doc_preview.close()
  end)

  it("preview cursor on each heading lands on that heading in the source", function()
    local s = open()
    vim.api.nvim_set_current_win(s.prev_win)
    local n = vim.api.nvim_buf_line_count(s.prev_buf)
    for _, h in ipairs(headings()) do
      for row = 1, n do
        if line_of(s.prev_win, row):find(h.text, 1, true) then
          vim.api.nvim_win_set_cursor(s.prev_win, { row, 0 })
          vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.prev_buf })
          assert.equals(h.line, vim.api.nvim_win_get_cursor(s.src_win)[1], h.text)
          break
        end
      end
    end
    doc_preview.close()
  end)

  it("walking the whole source keeps both cursors stable and in order", function()
    local s = open()
    local last = 0
    local skip = footnote_lines()
    local count = vim.api.nvim_buf_line_count(s.src_buf)
    for line = 1, count do
      vim.api.nvim_win_set_cursor(s.src_win, { line, 0 })
      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.src_buf })
      vim.api.nvim_exec_autocmds("WinScrolled", { pattern = tostring(s.src_win) })
      vim.wait(1)
      local prev = vim.api.nvim_win_get_cursor(s.prev_win)[1]
      if not skip[line] then
        assert.is_true(prev >= last, "preview moved backwards at source line " .. line)
        last = prev
      end
      assert.equals(line, vim.api.nvim_win_get_cursor(s.src_win)[1], "source cursor drifted")
    end
    doc_preview.close()
  end)
end)
