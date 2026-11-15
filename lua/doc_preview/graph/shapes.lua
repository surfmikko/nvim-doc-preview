-- Node shape table (doc/diagram-model.md 1): shape name -> border glyphs and
-- label padding, drawn on boxes of any height (3 lines for one-line labels).
-- `glyphs` are the fixed border glyphs per charset (nil: mergeable line cells),
-- `extra` decorates the box afterwards. Unknown names fall back to rect.
local text = require("doc_preview.core.text")

local M = {}

local function glyphs(tl, tr, bl, br, vl, vr)
  return { h = "─", v = "│", tl = tl, tr = tr, bl = bl, br = br, vl = vl, vr = vr }
end

local function ascii(tl, tr, bl, br, vl, vr)
  return { h = "-", v = "|", tl = tl, tr = tr, bl = bl, br = br, vl = vl, vr = vr }
end

-- Put `left` and `right` on every label row, `inset` cells inside the border.
local function sides(left, right, inset)
  return function(c, x, y, w, h, hl)
    for j = 1, h - 2 do
      c:put(x + inset, y + j, left, hl)
      c:put(x + w - 1 - inset, y + j, right, hl)
    end
  end
end

local function bars(c, x, y, w, h, hl)
  c:vline(x + 1, y, h, hl)
  c:vline(x + w - 2, y, h, hl)
end

local function base(c, x, y, w, h, hl)
  local row = (c.charset == "ascii" and "=" or "═"):rep(w - 2)
  c:put(x + 1, y + h - 1, row, hl)
end

-- Glyph-only shapes (state diagrams): one marker cell, no label.
local function marker(uni, asc)
  return function(c, x, y, w, h, hl)
    local row = c.charset == "ascii" and asc or uni
    c:put(x + math.floor((w - text.width(row)) / 2), y + math.floor((h - 1) / 2), row, hl)
  end
end

-- Fork/join bar: thick, horizontal on a wide box, vertical on a tall one.
local function bar(c, x, y, w, h, hl)
  local is_ascii = c.charset == "ascii"
  if h > w then
    for j = 0, h - 1 do
      c:put(x, y + j, is_ascii and "|" or "┃", hl)
    end
  else
    c:put(x, y, (is_ascii and "=" or "━"):rep(w), hl)
  end
end

local SHAPES = {
  start = { pad = 0, bare = true, size = { 3, 1 }, paint = marker("●", "(*)") },
  ["end"] = { pad = 0, bare = true, size = { 3, 1 }, paint = marker("◉", "(@)") },
  choice = {
    pad = 1,
    bare = true,
    size = { 5, 3 },
    unicode = glyphs("╱", "╲", "╲", "╱", "<", ">"),
    ascii = ascii("/", "\\", "\\", "/", "<", ">"),
  },
  bar = { pad = 0, bare = true, size = { 7, 1 }, vsize = { 1, 3 }, paint = bar },
  rect = { pad = 1 },
  record = { pad = 1 },
  round = {
    pad = 1,
    unicode = glyphs("╭", "╮", "╰", "╯"),
    ascii = ascii(".", ".", "'", "'"),
  },
  stadium = {
    pad = 1,
    unicode = glyphs("╭", "╮", "╰", "╯", "(", ")"),
    ascii = ascii(".", ".", "'", "'", "(", ")"),
  },
  subroutine = { pad = 2, extra = bars },
  circle = {
    pad = 2,
    unicode = glyphs("╭", "╮", "╰", "╯", "(", ")"),
    ascii = ascii(".", ".", "'", "'", "(", ")"),
    extra = sides("(", ")", 1),
  },
  rhombus = {
    pad = 1,
    unicode = glyphs("╱", "╲", "╲", "╱", "<", ">"),
    ascii = ascii("/", "\\", "\\", "/", "<", ">"),
  },
  hexagon = {
    pad = 1,
    unicode = glyphs("┌", "┐", "└", "┘", "<", ">"),
    ascii = ascii("+", "+", "+", "+", "<", ">"),
  },
  cylinder = {
    pad = 1,
    unicode = glyphs("╭", "╮", "╰", "╯"),
    ascii = ascii(".", ".", "'", "'"),
    extra = base,
  },
}

local function lines_of(label)
  return vim.split(label, "\n", { plain = true })
end

-- Sections of node `n` as line lists: the title first, then the non-empty
-- `rows` sections; a plain node is the title only.
---@return string[][]
function M.sections(n)
  local list = { lines_of(n.label) }
  for _, section in ipairs(n.rows or {}) do
    if #section > 0 then
      list[#list + 1] = section
    end
  end
  return list
end

-- Box size { w, h } of node `n`: widest line plus padding and border; one row
-- per line plus a divider row between sections.
---@return integer w
---@return integer h
function M.size(n, vertical)
  local fixed = SHAPES[n.shape] and SHAPES[n.shape].size
  if fixed then
    local v = vertical and SHAPES[n.shape].vsize
    return (v or fixed)[1], (v or fixed)[2]
  end
  local sections = M.sections(n)
  local widest, h = 0, 2 + #sections - 1
  for _, section in ipairs(sections) do
    for _, line in ipairs(section) do
      widest = math.max(widest, text.width(line))
    end
    h = h + #section
  end
  return widest + 2 * M.get(n.shape).pad + 2, h
end

-- Divider rows `├──┤` of a record box at rows `ys`.
function M.divide(c, x, y, w, ys, hl)
  local is_ascii = c.charset == "ascii"
  local row = (is_ascii and "+" or "├")
    .. (is_ascii and "-" or "─"):rep(math.max(w - 2, 0))
    .. (is_ascii and "+" or "┤")
  for _, dy in ipairs(ys) do
    c:put(x, y + dy, row, hl)
  end
end

---@param name? string
---@return { pad: integer, unicode?: table, ascii?: table, extra?: function }
function M.get(name)
  return SHAPES[name] or SHAPES.rect
end

-- Draw the border (and decoration) of shape `name` on canvas `c`.
---@param c table  core.canvas
function M.draw(name, c, x, y, w, h, hl)
  local shape = M.get(name)
  if shape.paint then
    return shape.paint(c, x, y, w, h, hl)
  end
  c:box(x, y, w, h, hl, shape[c.charset])
  if shape.extra and w >= 2 and h >= 2 then
    shape.extra(c, x, y, w, h, hl)
  end
end

return M
