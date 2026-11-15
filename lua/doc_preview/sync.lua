-- Autocmds and debounce for one session (doc/architecture.md 5.3).
-- Knows the session's fields but not the Session module.
local config = require("doc_preview.config")

local M = {}

local function attach_resize(s, group)
  vim.api.nvim_create_autocmd("WinResized", {
    group = group,
    callback = function()
      local wins = vim.v.event.windows or {}
      if not s.closed and s.prev_win and vim.tbl_contains(wins, s.prev_win) then
        s.handlers.resized(s)
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if not s.closed then
        s.handlers.resized(s)
      end
    end,
  })
end

-- Large-file guard (doc/architecture.md 9): over the threshold edits are
-- ignored and only a save refreshes the preview.
function M.is_large(s)
  if not vim.api.nvim_buf_is_valid(s.src_buf) then
    return false
  end
  return vim.api.nvim_buf_line_count(s.src_buf) > config.options.large_file_lines
end

local function attach_edit(s, group)
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = s.src_buf,
    callback = function()
      if M.is_large(s) then
        s.handlers.large(s)
      else
        M.changed(s)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    buffer = s.src_buf,
    callback = function()
      if M.is_large(s) then
        M.changed(s)
      end
    end,
  })
end

local function attach_window_sync(s, group, on)
  local src_pat, prev_pat = tostring(s.src_win), tostring(s.prev_win)
  on("WinScrolled", src_pat, function(x)
    M.to_preview(x, "scroll")
  end)
  on("WinScrolled", prev_pat, function(x)
    M.to_source(x, "scroll")
  end)
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = s.src_buf,
    callback = function()
      if vim.api.nvim_get_current_win() == s.src_win then
        M.to_preview(s, "cursor")
      end
    end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = s.prev_buf,
    callback = function()
      if vim.api.nvim_get_current_win() == s.prev_win then
        M.to_source(s, "cursor")
      end
    end,
  })
end

local function attach_win_closed(s, group, handlers)
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(s.prev_win),
    callback = function()
      s.prev_win = nil
      handlers.close(s)
    end,
  })
end

---@param s table session
---@param handlers { changed: fun(s), render: fun(s), close: fun(s), resized: fun(s), large: fun(s) }
---@param debounce_ms integer
function M.attach(s, handlers, debounce_ms)
  s.augroup = "DocPreview" .. s.src_buf
  s.timer = vim.uv.new_timer()
  s.pending = false
  s.debounce_ms = debounce_ms
  s.handlers = handlers
  local group = vim.api.nvim_create_augroup(s.augroup, { clear = true })

  attach_edit(s, group)
  s.guard = {}
  s.base = {}
  s.sync_flags = vim.deepcopy(config.options.sync)
  s.sync_enabled = s.sync_flags.cursor or s.sync_flags.scroll
  local function on(event, pattern, fn)
    vim.api.nvim_create_autocmd(event, {
      group = group,
      pattern = pattern,
      callback = function()
        if s.closed then
          return
        end
        fn(s)
      end,
    })
  end
  attach_resize(s, group)
  if s.layout ~= "replace" then
    attach_window_sync(s, group, on)
  end
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    buffer = s.src_buf,
    callback = function()
      handlers.close(s)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = s.prev_buf,
    callback = function()
      s.prev_buf = nil
      handlers.close(s)
    end,
  })
  if s.layout ~= "replace" then
    attach_win_closed(s, group, handlers)
  end
end

-- Cursor/scroll sync (doc/architecture.md 5.4). Works on s.output, the
-- last applied render; does nothing before the first one lands.
local function view(win)
  local line = vim.api.nvim_win_get_cursor(win)[1]
  return line, vim.fn.getwininfo(win)[1].topline
end

-- Move `to` so `line` is shown. The resulting position is recorded in
-- s.guard so the events it causes (delivered later by the event loop) are
-- recognised and ignored.
local function move(s, to, line, top)
  local count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(to))
  line = math.max(1, math.min(line, count))
  top = math.max(line - vim.api.nvim_win_get_height(to) + 1, math.min(top, line), 1)
  vim.api.nvim_win_call(to, function()
    vim.fn.winrestview({ lnum = line, col = 0, topline = top })
  end)
  s.guard[to] = { view(to) }
end

-- Where `to` should start. The origin topline only changes when the origin
-- scrolls; then `to` keeps the origin's window row (never against the
-- direction of travel, the map is not 1:1). While the origin merely moves its
-- cursor, `to` keeps its topline (only scrolling if the target leaves the
-- window), so the text does not shift on every j/k.
local function top_for(s, from, to, line, top, target)
  local b = s.base[from]
  if b and b.top == top then
    return b.ptop
  end
  local ptop = math.max(1, target - (line - top))
  local cur_top = vim.fn.getwininfo(to)[1].topline
  local dir = line - (b and b.line or line)
  if (dir > 0 and ptop < cur_top) or (dir < 0 and ptop > cur_top) then
    ptop = cur_top
  end
  s.base[from] = { top = top, ptop = ptop, line = line }
  return ptop
end

-- `kind` is "cursor" or "scroll" for events, nil for an unconditional resync.
local function enabled_for(s, kind)
  return s.sync_enabled and (kind == nil or s.sync_flags[kind])
end

local function follow(s, from, to, convert, kind)
  if
    not enabled_for(s, kind)
    or not s.output
    or not vim.api.nvim_win_is_valid(from)
    or not vim.api.nvim_win_is_valid(to)
  then
    return
  end
  local g = s.guard[from]
  local line, top = view(from)
  if g and g[1] == line and g[2] == top then
    return -- caused by our own move
  end
  s.guard[from] = nil
  local target = convert(s.output, line)
  if target then
    move(s, to, target, top_for(s, from, to, line, top, target))
  end
end

function M.to_preview(s, kind)
  follow(s, s.src_win, s.prev_win, s.output and s.output.src_to_out, kind)
end

function M.to_source(s, kind)
  follow(s, s.prev_win, s.src_win, s.output and s.output.out_to_src, kind)
end

function M.set_enabled(s, enabled)
  if s.layout == "replace" then
    return -- no cursor/scroll sync in the shared window
  end
  s.sync_enabled = enabled
  if enabled then
    s.sync_flags = { cursor = true, scroll = true }
    s.guard = {}
    s.base = {}
    M.to_preview(s)
  end
end

-- Source text changed: cancel running work now, render after the debounce.
function M.changed(s)
  s.handlers.changed(s)
  s.pending = true
  s.timer:stop()
  s.timer:start(
    s.debounce_ms,
    0,
    vim.schedule_wrap(function()
      if s.pending then
        s.pending = false
        s.handlers.render(s)
      end
    end)
  )
end

function M.detach(s)
  s.pending = false
  if s.timer and not s.timer:is_closing() then
    s.timer:stop()
    s.timer:close()
  end
  pcall(vim.api.nvim_del_augroup_by_name, s.augroup)
end

return M
