-- Boxed, dimmed source listing with a title: fallback for a failing or
-- unsupported block (doc/architecture.md 3, 4.5). Pure; never raises on
-- any lines/width. One map entry covers the whole block.
local box = require("doc_preview.core.box")
local out = require("doc_preview.core.out")
local text = require("doc_preview.core.text")

local M = {}

local BORDER, BODY = "DocPreviewDiagramBorder", "DocPreviewErrbox"
local MIN_BOXED = 5 -- two borders, two paddings, one column

local function wrap_all(strs, width)
  local rows = {}
  for _, s in ipairs(strs) do
    for _, r in ipairs(text.hard_wrap(text.expand_tabs(s), width)) do
      rows[#rows + 1] = r
    end
  end
  return rows
end

local function widest(rows)
  local w = 0
  for _, r in ipairs(rows) do
    w = math.max(w, text.width(r))
  end
  return w
end

local function plain(o, rows)
  for _, r in ipairs(rows) do
    local n = o:add_line(r)
    if #r > 0 then
      o:add_span(n, 0, #r, BODY)
    end
  end
end

local function border_row(o, g, position, inner)
  local set = g[position]
  local line = set[1] .. g.h:rep(inner + 2) .. set[3]
  o:add_span(o:add_line(line), 0, #line, BORDER)
end

local function text_row(o, g, s, inner)
  local line = g.v .. " " .. text.pad(s, inner) .. " " .. g.v
  local n = o:add_line(line)
  o:add_span(n, 0, #g.v, BORDER)
  if #s > 0 then
    o:add_span(n, #g.v + 1, #g.v + 1 + #s, BODY)
  end
  o:add_span(n, #line - #g.v, #line, BORDER)
end

local function boxed(o, g, title_rows, src_rows, inner)
  border_row(o, g, "top", inner)
  for _, r in ipairs(title_rows) do
    text_row(o, g, r, inner)
  end
  if #src_rows > 0 then
    border_row(o, g, "mid", inner)
    for _, r in ipairs(src_rows) do
      text_row(o, g, r, inner)
    end
  end
  border_row(o, g, "bottom", inner)
end

---@param lines string[]  block source
---@param ctx { width: integer, charset?: string }
---@param title string
---@return doc_preview.Output
function M.render(lines, ctx, title)
  local o = out.new()
  local avail = ctx.width - 4
  if ctx.width < MIN_BOXED then
    plain(o, wrap_all({ title }, ctx.width))
    plain(o, wrap_all(lines, ctx.width))
  else
    local title_rows = wrap_all({ title }, avail)
    local src_rows = wrap_all(lines, avail)
    local inner = math.max(widest(title_rows), widest(src_rows))
    boxed(o, box.glyphs(ctx.charset), title_rows, src_rows, inner)
  end
  o:add_map(1, #o.lines, 1, math.max(#lines, 1))
  return o
end

return M
