-- 2D character grid for diagrams (doc/architecture.md 3, doc/diagram-model.md 1).
-- Cells are display-width aware: a wide char occupies two cells (head plus a
-- continuation cell). Line glyphs keep a connection mask so crossings and
-- junctions merge into the right glyph. Pure; coordinates are 0-based.
local out = require("doc_preview.core.out")
local text = require("doc_preview.core.text")

local bor = bit.bor

local M = {}

local N, E, S, W = 1, 2, 4, 8
local DIRS = { up = N, right = E, down = S, left = W }

local UNICODE_LINES = {
  [N] = "│",
  [S] = "│",
  [N + S] = "│",
  [E] = "─",
  [W] = "─",
  [E + W] = "─",
  [N + E] = "└",
  [E + S] = "┌",
  [S + W] = "┐",
  [N + W] = "┘",
  [N + E + S] = "├",
  [E + S + W] = "┬",
  [N + S + W] = "┤",
  [N + E + W] = "┴",
  [N + E + S + W] = "┼",
}

local THICK_LINES = {
  [N] = "┃",
  [S] = "┃",
  [N + S] = "┃",
  [E] = "━",
  [W] = "━",
  [E + W] = "━",
  [N + E] = "┗",
  [E + S] = "┏",
  [S + W] = "┓",
  [N + W] = "┛",
  [N + E + S] = "┣",
  [E + S + W] = "┳",
  [N + S + W] = "┫",
  [N + E + W] = "┻",
  [N + E + S + W] = "╋",
}

-- Straight dotted runs; junctions and corners keep the solid glyphs.
local DOTTED = { unicode = { v = "┆", h = "┄" }, ascii = { v = ":", h = "." } }
local THICK_ASCII = { v = "!", h = "=" }

local HEADS = {
  unicode = { up = "▲", right = "▶", down = "▼", left = "◀" },
  ascii = { up = "^", right = ">", down = "v", left = "<" },
}

local CHAR = "[%z\1-\127\194-\244][\128-\191]*"

local Canvas = {}
Canvas.__index = Canvas

---@param width integer
---@param height integer
---@param charset? "unicode"|"ascii"
function M.new(width, height, charset)
  local self = setmetatable({ w = width, h = height, charset = charset or "unicode" }, Canvas)
  self.rows = {}
  for y = 1, height do
    self.rows[y] = {}
  end
  return self
end

local function inside(self, x, y)
  return x >= 0 and x < self.w and y >= 0 and y < self.h
end

local function cell(self, x, y)
  return inside(self, x, y) and self.rows[y + 1][x + 1] or nil
end

-- Empty the cell at x, and the other half when it belongs to a wide char.
local function clear(self, x, y)
  local row = self.rows[y + 1]
  local c = row[x + 1]
  if not c then
    return
  end
  if c.cont then
    row[x] = nil
  elseif c.width == 2 then
    row[x + 2] = nil
  end
  row[x + 1] = nil
end

local function set(self, x, y, c)
  if inside(self, x, y) then
    clear(self, x, y)
    self.rows[y + 1][x + 1] = c
  end
end

local function put_wide(self, x, y, ch, hl)
  if x + 1 >= self.w then
    set(self, x, y, { ch = "?", hl = hl, width = 1 })
    return
  end
  clear(self, x + 1, y)
  set(self, x, y, { ch = ch, hl = hl, width = 2 })
  self.rows[y + 1][x + 2] = { cont = true, hl = hl }
end

---@param x integer
---@param y integer
---@param str string
---@param hl? string
function Canvas:put(x, y, str, hl)
  local last
  for ch in str:gmatch(CHAR) do
    local cw = text.width(ch)
    if cw == 0 and last then
      last.ch = last.ch .. ch
    elseif cw > 0 then
      if inside(self, x, y) then
        if cw == 2 then
          put_wide(self, x, y, ch, hl)
        else
          set(self, x, y, { ch = ch, hl = hl, width = 1 })
        end
        last = cell(self, x, y)
      end
      x = x + cw
    end
  end
end

local function straight(mask)
  if mask == N + S or mask == N or mask == S then
    return "v"
  end
  if mask == E + W or mask == E or mask == W then
    return "h"
  end
end

local function ascii_glyph(dir)
  if dir == "v" then
    return "|"
  end
  return dir == "h" and "-" or "+"
end

local function line_glyph(self, mask, style)
  local dir = straight(mask)
  if style == "dotted" and dir then
    return DOTTED[self.charset][dir]
  end
  if style == "thick" and dir and self.charset == "ascii" then
    return THICK_ASCII[dir]
  end
  if self.charset == "ascii" then
    return ascii_glyph(dir)
  end
  return (style == "thick" and THICK_LINES or UNICODE_LINES)[mask]
end

-- OR `mask` into the line cell at x, y (a non-line cell is replaced).
-- `style` is solid (default), dotted or thick; the latest style wins.
local function merge(self, x, y, mask, hl, style)
  if not inside(self, x, y) then
    return
  end
  local c = cell(self, x, y)
  local old = c and c.mask or 0
  local m = bor(old, mask)
  set(self, x, y, { ch = line_glyph(self, m, style), hl = hl or (c and c.hl), width = 1, mask = m })
end

---@param x integer
---@param y integer
---@param len integer
---@param hl? string
---@param style? "solid"|"dotted"|"thick"
function Canvas:hline(x, y, len, hl, style)
  for i = 0, len - 1 do
    local mask = bor(i > 0 and W or 0, i < len - 1 and E or 0)
    merge(self, x + i, y, mask == 0 and E + W or mask, hl, style)
  end
end

---@param x integer
---@param y integer
---@param len integer
---@param hl? string
---@param style? "solid"|"dotted"|"thick"
function Canvas:vline(x, y, len, hl, style)
  for i = 0, len - 1 do
    local mask = bor(i > 0 and N or 0, i < len - 1 and S or 0)
    merge(self, x, y + i, mask == 0 and N + S or mask, hl, style)
  end
end

-- Border of a w x h box with its top-left corner at x, y. `glyphs` (optional
-- { h, v, tl, tr, bl, br, vl?, vr? }; vl/vr override v per side) draws fixed
-- glyphs (e.g. rounded corners) that do not merge; by default the border is made of mergeable line cells.
---@param glyphs? table
function Canvas:box(x, y, w, h, hl, glyphs)
  if w < 2 or h < 2 then
    return
  end
  if glyphs then
    self:put(x + 1, y, glyphs.h:rep(w - 2), hl)
    self:put(x + 1, y + h - 1, glyphs.h:rep(w - 2), hl)
    for j = 1, h - 2 do
      self:put(x, y + j, glyphs.vl or glyphs.v, hl)
      self:put(x + w - 1, y + j, glyphs.vr or glyphs.v, hl)
    end
    self:put(x, y, glyphs.tl, hl)
    self:put(x + w - 1, y, glyphs.tr, hl)
    self:put(x, y + h - 1, glyphs.bl, hl)
    self:put(x + w - 1, y + h - 1, glyphs.br, hl)
    return
  end
  merge(self, x, y, E + S, hl)
  merge(self, x + w - 1, y, S + W, hl)
  merge(self, x, y + h - 1, N + E, hl)
  merge(self, x + w - 1, y + h - 1, N + W, hl)
  for i = 1, w - 2 do
    merge(self, x + i, y, E + W, hl)
    merge(self, x + i, y + h - 1, E + W, hl)
  end
  for j = 1, h - 2 do
    merge(self, x, y + j, N + S, hl)
    merge(self, x + w - 1, y + j, N + S, hl)
  end
end

-- True when the `len` cells from x, y are inside the grid and still empty.
function Canvas:is_blank(x, y, len)
  for i = 0, len - 1 do
    if not inside(self, x + i, y) or cell(self, x + i, y) then
      return false
    end
  end
  return true
end

-- Arrow head pointing `dir` ("up"|"right"|"down"|"left").
function Canvas:arrow(x, y, dir, hl)
  assert(DIRS[dir], "bad direction")
  self:put(x, y, HEADS[self.charset][dir], hl)
end

local function row_string(row, width)
  local parts, spans, col, last = {}, {}, 0, nil
  for x = 1, width do
    local c = row[x]
    if c and not c.cont then
      parts[#parts + 1] = c.ch
      if c.hl and c.ch ~= " " then
        if last and last.hl_group == c.hl and last.col_end == col then
          last.col_end = col + #c.ch
        else
          last = { hl_group = c.hl, col_start = col, col_end = col + #c.ch }
          spans[#spans + 1] = last
        end
      end
      col = col + #c.ch
    elseif not c then
      parts[#parts + 1] = " "
      col = col + 1
    end
  end
  return table.concat(parts), spans
end

-- Lines (trailing blanks trimmed) plus highlight spans; no source map.
---@return doc_preview.Output
function Canvas:to_output()
  local o = out.new()
  for y = 1, self.h do
    local s, spans = row_string(self.rows[y], self.w)
    local trimmed = s:gsub("%s+$", "")
    local n = o:add_line(trimmed)
    for _, sp in ipairs(spans) do
      if sp.col_start < #trimmed then
        o:add_span(n, sp.col_start, math.min(sp.col_end, #trimmed), sp.hl_group)
      end
    end
  end
  return o
end

return M
