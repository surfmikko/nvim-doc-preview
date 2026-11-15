-- One Session per source buffer: preview buffer/window and the async
-- render job (doc/architecture.md 5.1, 5.3).
local config = require("doc_preview.config")
local highlight = require("doc_preview.core.highlight")
local job = require("doc_preview.core.job")
local diagram_file = require("doc_preview.document.diagram_file")
local markdown = require("doc_preview.markdown.block")
local render = require("doc_preview.document.render")
local replace = require("doc_preview.replace")
local sync = require("doc_preview.sync")

local M = {}

local sessions = {} -- src_buf -> Session

-- Accepts the source buffer or, for `replace`, the preview buffer that
-- stands in for it in the user's window.
function M.get(buf)
  if sessions[buf] then
    return sessions[buf]
  end
  for _, s in pairs(sessions) do
    if s.prev_buf == buf then
      return s
    end
  end
end

local function create_preview_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  -- Buffer names are unique: a second preview gets its buffer number.
  if not pcall(vim.api.nvim_buf_set_name, buf, "Preview") then
    vim.api.nvim_buf_set_name(buf, "Preview " .. buf)
  end
  return buf
end

-- A new change or resize: abandon any running job, results of older
-- generations are never applied.
function M.invalidate(s)
  s.generation = s.generation + 1
  if s.job then
    s.job.cancel()
    s.job = nil
  end
end

local function apply(s, output)
  vim.bo[s.prev_buf].modifiable = true
  vim.api.nvim_buf_clear_namespace(s.prev_buf, s.ns, 0, -1)
  vim.api.nvim_buf_set_lines(s.prev_buf, 0, -1, false, output.lines)
  highlight.apply(s.prev_buf, s.ns, output.spans)
  vim.bo[s.prev_buf].modifiable = false
  local first = s.output == nil
  s.output = output
  if first and s.layout == "replace" then
    replace.first_render(s)
  end
  -- Keep the preview aligned with the source after content changed, unless
  -- the user is working in the preview.
  local force = s.resync
  s.resync = nil
  if
    s.layout ~= "replace"
    and s.prev_win
    and (force or vim.api.nvim_get_current_win() ~= s.prev_win)
  then
    s.guard[s.src_win] = nil
    s.base = {}
    sync.to_preview(s)
  end
end

-- Hard-wrap width: the preview window width, capped by max_width.
function M.width(s)
  local max = config.options.max_width
  if s.prev_win and vim.api.nvim_win_is_valid(s.prev_win) then
    return math.min(vim.api.nvim_win_get_width(s.prev_win), max)
  end
  return max
end

-- Per-buffer frontend choice: diagram files or markdown (default).
local function frontend_for(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  return diagram_file.matches(vim.bo[buf].filetype, name) and diagram_file or markdown
end

function M.render(s)
  local ctx = {
    width = M.width(s),
    charset = config.options.charset,
    engines = config.options.engines,
  }
  s.width = ctx.width
  local gen = s.generation
  local lines = vim.api.nvim_buf_get_lines(s.src_buf, 0, -1, false)
  s.job = job.run(function()
    return render.render(s.frontend.parse(lines), ctx)
  end, {
    slice_ms = config.options.slice_ms,
    on_done = function(output)
      if s.closed or gen ~= s.generation then
        return
      end
      s.job = nil
      apply(s, output)
      vim.api.nvim_exec_autocmds("User", {
        pattern = "DocPreviewRendered",
        data = { buf = s.src_buf, generation = gen },
      })
    end,
    on_error = function(err)
      s.job = nil
      vim.notify("doc_preview: render failed: " .. tostring(err), vim.log.levels.ERROR)
    end,
  })
end

-- Preview or editor resized: re-render only when the effective width changed.
-- Neovim already coalesces resize events, so no debounce.
function M.resized(s)
  if s.closed or M.width(s) == s.width then
    return
  end
  s.resync = true
  M.invalidate(s)
  M.render(s)
end

-- One warning per session, however often the buffer crosses the threshold.
function M.warn_large(s)
  if s.warned then
    return
  end
  s.warned = true
  local msg = "doc_preview: %d lines exceeds large_file_lines (%d); preview refreshes on save only"
  local count = vim.api.nvim_buf_line_count(s.src_buf)
  vim.notify(msg:format(count, config.options.large_file_lines), vim.log.levels.WARN)
end

local SPLITS = { vsplit = "right", hsplit = "below" }

-- Buffer-local close map from config.options.keymaps.close (`false` = none).
-- It dies with the preview buffer.
local function set_keymaps(s)
  local lhs = config.options.keymaps.close
  if lhs then
    vim.keymap.set("n", lhs, function()
      M.close(s)
    end, { buffer = s.prev_buf, nowait = true, silent = true })
  end
end

---@param src_buf integer
---@param layout? string defaults to config.options.layout
---@return table? session
function M.open(src_buf, layout)
  layout = layout or config.options.layout
  local existing = sessions[src_buf]
  if existing then
    if existing.layout == layout then
      return existing
    end
    M.close(existing)
  end
  highlight.setup()
  local prev_buf = create_preview_buf()
  local s = {
    src_buf = src_buf,
    frontend = frontend_for(src_buf),
    layout = layout,
    prev_buf = prev_buf,
    src_win = vim.api.nvim_get_current_win(),
    generation = 0,
    ns = vim.api.nvim_create_namespace("doc_preview.session." .. src_buf),
  }
  if layout == "replace" then
    replace.enter(s, prev_buf)
  else
    s.prev_win = vim.api.nvim_open_win(prev_buf, false, { split = SPLITS[layout] })
  end
  sessions[src_buf] = s
  set_keymaps(s)
  sync.attach(s, {
    changed = M.invalidate,
    render = M.render,
    close = M.close,
    resized = M.resized,
    large = M.warn_large,
  }, config.options.debounce_ms)
  M.invalidate(s)
  M.render(s)
  if sync.is_large(s) then
    M.warn_large(s)
  end
  return s
end

function M.close(s)
  if s.closed then
    return
  end
  s.closed = true
  sessions[s.src_buf] = nil
  M.invalidate(s)
  sync.detach(s)
  if s.layout == "replace" then
    replace.leave(s)
  elseif s.prev_win and vim.api.nvim_win_is_valid(s.prev_win) and #vim.api.nvim_list_wins() > 1 then
    vim.api.nvim_win_close(s.prev_win, true)
  end
  if s.prev_buf and vim.api.nvim_buf_is_valid(s.prev_buf) then
    vim.api.nvim_buf_clear_namespace(s.prev_buf, s.ns, 0, -1)
    vim.api.nvim_buf_delete(s.prev_buf, { force = true })
  end
end

-- Test hook: block until no debounce is pending and no job is running.
-- Over large_file_lines an unsaved edit arms no debounce and starts no job,
-- so this returns immediately after it.
function M.wait(s, timeout)
  return vim.wait(timeout, function()
    return not s.pending and not s.job
  end, 5)
end

return M
