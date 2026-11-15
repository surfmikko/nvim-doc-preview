local doc_preview = require("doc_preview")
local render = require("doc_preview.document.render")

vim.cmd("runtime plugin/doc_preview.lua")

-- 40 paragraphs, two blank lines between them: paragraph i is source
-- line 3i-2 and preview line 2i-1.
local function lines()
  local t = {}
  for i = 1, 40 do
    vim.list_extend(t, { "p" .. i, "", "" })
  end
  return t
end

local function open()
  vim.cmd("enew")
  local src = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(src, 0, -1, false, lines())
  vim.cmd("DocPreview open")
  return doc_preview.session(src)
end

local function settle(s)
  assert.is_true(doc_preview.wait(s, 2000))
  vim.wait(50) -- let queued CursorMoved/WinScrolled events run
end

local function cursor(win)
  return vim.api.nvim_win_get_cursor(win)[1]
end

describe("DocPreview scroll sync", function()
  after_each(function()
    render.test_hook = nil
    pcall(vim.cmd, "only")
  end)

  it("source cursor moves the preview cursor", function()
    local s = open()
    settle(s)
    vim.api.nvim_win_set_cursor(s.src_win, { 31, 0 }) -- p11
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.src_buf })
    assert.equals(21, cursor(s.prev_win))
    doc_preview.close()
  end)

  it("preview cursor moves the source cursor", function()
    local s = open()
    settle(s)
    vim.api.nvim_set_current_win(s.prev_win)
    vim.api.nvim_win_set_cursor(s.prev_win, { 21, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.prev_buf })
    assert.equals(31, cursor(s.src_win))
    doc_preview.close()
  end)

  it("keeps the window row and does not oscillate", function()
    local s = open()
    settle(s)
    vim.api.nvim_win_set_height(s.src_win, 10)
    vim.api.nvim_win_set_cursor(s.src_win, { 61, 0 })
    vim.cmd("normal! zt")
    vim.api.nvim_win_set_cursor(s.src_win, { 64, 0 }) -- row 3 of window
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.src_buf })
    local prev_top = vim.fn.getwininfo(s.prev_win)[1].topline
    assert.equals(cursor(s.prev_win) - 3, prev_top)
    local src_pos = cursor(s.src_win)
    vim.wait(100)
    assert.equals(src_pos, cursor(s.src_win))
    assert.equals(prev_top, vim.fn.getwininfo(s.prev_win)[1].topline)
    doc_preview.close()
  end)

  it("snaps an unmapped source line to the nearest block", function()
    local s = open()
    settle(s)
    vim.api.nvim_win_set_cursor(s.src_win, { 3, 0 }) -- blank line right before p2
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.src_buf })
    assert.equals(3, cursor(s.prev_win))
    doc_preview.close()
  end)

  it("is a no-op before the first render", function()
    local s = open()
    assert.is_nil(s.output)
    vim.api.nvim_win_set_cursor(s.src_win, { 31, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.src_buf })
    assert.equals(1, cursor(s.prev_win))
    doc_preview.close()
  end)

  it("uses the last applied output while a re-render runs", function()
    local s = open()
    settle(s)
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = s.src_buf })
    assert.is_true(s.pending)
    vim.api.nvim_win_set_cursor(s.src_win, { 31, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.src_buf })
    assert.equals(21, cursor(s.prev_win))
    settle(s)
    assert.equals(21, cursor(s.prev_win))
    doc_preview.close()
  end)

  it("leaves no autocmds behind after close", function()
    local s = open()
    settle(s)
    local group = s.augroup
    doc_preview.close()
    assert.is_false(pcall(vim.api.nvim_get_autocmds, { group = group }))
  end)
end)
