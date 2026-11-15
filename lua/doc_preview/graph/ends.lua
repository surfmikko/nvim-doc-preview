-- Edge end decorations (doc/architecture.md 10 item 1): glyphs per kind and
-- direction, and candidate spots for the text (cardinality) beside an end.
-- Pure; `dir` is the direction the end points to ("up"|"right"|"down"|"left").
local M = {}

local GLYPHS = {
  unicode = {
    open = { up = "^", right = ">", down = "v", left = "<" },
    triangle = { up = "△", right = "▷", down = "▽", left = "◁" },
    diamond = "◇",
    diamond_filled = "◆",
    circle = "o",
    cross = "x",
  },
  ascii = {
    open = { up = "^", right = ">", down = "v", left = "<" },
    triangle = { up = "^", right = ">", down = "v", left = "<" },
    diamond = "o",
    diamond_filled = "*",
    circle = "o",
    cross = "x",
  },
}

-- Glyph of a decorated end, nil for none and for the plain filled arrow
-- (drawn by canvas:arrow).
---@return string|nil
function M.glyph(kind, dir, charset)
  local g = GLYPHS[charset or "unicode"][kind]
  if type(g) == "table" then
    return g[dir]
  end
  return g
end

-- ER cardinality ends are two cells along the line: { near the node, far }.
-- The bar is perpendicular to the line, the crow's foot spreads toward the node.
local BAR = {
  unicode = { vertical = "╪", horizontal = "╫" },
  ascii = { vertical = "+", horizontal = "+" },
}
local CROW = {
  unicode = { up = "┬", down = "┴", left = "├", right = "┤" },
  ascii = { up = "v", down = "^", left = ">", right = "<" },
}
local CARDINALITY = {
  one = { "bar", "bar" },
  zero_one = { "bar", "zero" },
  zero_many = { "crow", "zero" },
  one_many = { "crow", "bar" },
}

---@return boolean
function M.is_cardinality(kind)
  return CARDINALITY[kind] ~= nil
end

-- Glyphs { near, far } of cardinality `kind` at an end whose node lies `toward`.
---@return string[]
function M.cardinality(kind, toward, charset)
  charset = charset or "unicode"
  local axis = (toward == "up" or toward == "down") and "vertical" or "horizontal"
  local out = {}
  for i, part in ipairs(CARDINALITY[kind]) do
    out[i] = part == "zero" and "o" or part == "bar" and BAR[charset][axis] or CROW[charset][toward]
  end
  return out
end

-- Candidate top-left cells, best first, for a one-row text of display width
-- `w` beside the end cell `p`; `toward` is the direction of the node the end
-- belongs to. Beside a vertical line: right, then left of it. Beside a
-- horizontal one: above, then below, running along the gap away from the node.
---@return table[]
function M.spots(p, toward, w)
  if toward == "up" or toward == "down" then
    return { { x = p.x + 2, y = p.y }, { x = p.x - 1 - w, y = p.y } }
  end
  local x = toward == "right" and p.x - w + 1 or p.x
  return { { x = x, y = p.y - 1 }, { x = x, y = p.y + 1 } }
end

return M
