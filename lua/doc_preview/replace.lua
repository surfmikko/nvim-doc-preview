-- `replace` layout: the preview buffer takes over the user's window and the
-- source flips back on close (doc/architecture.md 5.1.1). The window is
-- never created or closed here.
local M = {}

-- Window-local options the preview wants; the old values are restored on
-- flip back since the window is the user's.
local PREVIEW_WO = { wrap = false, list = false, spell = false }

local function view(win)
  local line = vim.api.nvim_win_get_cursor(win)[1]
  return line, vim.fn.getwininfo(win)[1].topline
end

-- Cursor `line` of the other buffer with the same relative screen row.
local function place(win, line, cur, top)
  local count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
  line = math.max(1, math.min(line, count))
  vim.api.nvim_win_call(win, function()
    vim.fn.winrestview({ lnum = line, col = 0, topline = math.max(1, line - (cur - top)) })
  end)
end

---@param s table session; s.src_win is the shared window
---@param prev_buf integer
function M.enter(s, prev_buf)
  local win = s.src_win
  s.prev_win = win
  s.src_view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
  s.saved_wo = {}
  for name, value in pairs(PREVIEW_WO) do
    s.saved_wo[name] = vim.wo[win][name]
    vim.wo[win][name] = value
  end
  vim.api.nvim_win_set_buf(win, prev_buf)
end

-- First render landed: map the source cursor into the preview, once.
---@param s table session with s.output
function M.first_render(s)
  if s.placed or not vim.api.nvim_win_is_valid(s.prev_win) then
    return
  end
  s.placed = true
  local line = s.output:src_to_out(s.src_view.lnum)
  if line then
    place(s.prev_win, line, s.src_view.lnum, s.src_view.topline)
  end
  s.placed_at = { view(s.prev_win) }
end

-- Source cursor from the preview cursor, or nil to restore the saved view.
local function mapped(s, win)
  if not s.output or not s.placed_at then
    return nil
  end
  local line, top = view(win)
  if line == s.placed_at[1] and top == s.placed_at[2] then
    return nil
  end
  local target = s.output:out_to_src(line)
  return target and { target, line - top }
end

local function restore_wo(s, win)
  for name, value in pairs(s.saved_wo or {}) do
    vim.wo[win][name] = value
  end
end

-- Show the source buffer again and restore its view. The preview buffer is
-- wiped by bufhidden=wipe once it is hidden.
---@param s table session
function M.leave(s)
  local win = s.src_win
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end
  -- Preview already gone from the window (another buffer shown): no view
  -- restore, but the window is still the user's, so give its options back.
  if vim.api.nvim_win_get_buf(win) ~= s.prev_buf or not vim.api.nvim_buf_is_valid(s.src_buf) then
    restore_wo(s, win)
    return
  end
  local map = mapped(s, win)
  vim.api.nvim_win_set_buf(win, s.src_buf)
  restore_wo(s, win)
  vim.api.nvim_win_call(win, function()
    vim.fn.winrestview(s.src_view)
  end)
  if map then
    place(win, map[1], map[2] + 1, 1)
  end
end

return M
