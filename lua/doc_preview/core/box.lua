-- Box-drawing glyph sets and border rules for table grids (doc/architecture.md 3).
-- Pure functions. `charset` is "unicode" (default) or "ascii".
local M = {}

local SETS = {
  unicode = {
    h = "─",
    v = "│",
    top = { "┌", "┬", "┐" },
    mid = { "├", "┼", "┤" },
    bottom = { "└", "┴", "┘" },
    rule = "─",
    quote = "│ ",
    bullets = { "•", "◦", "▪" },
  },
  ascii = {
    h = "-",
    v = "|",
    top = { "+", "+", "+" },
    mid = { "+", "+", "+" },
    bottom = { "+", "+", "+" },
    rule = "-",
    quote = "| ",
    bullets = { "*", "-", "+" },
  },
}

local POSITIONS = { top = "top", header = "mid", row = "mid", bottom = "bottom" }

---@param charset? "unicode"|"ascii"
---@return table
function M.glyphs(charset)
  return SETS[charset or "unicode"] or SETS.unicode
end

---@param charset? "unicode"|"ascii"
---@return string
function M.rule_glyph(charset)
  return M.glyphs(charset).rule
end

---@param charset? "unicode"|"ascii"
---@return string
function M.quote_prefix(charset)
  return M.glyphs(charset).quote
end

-- Bullet for nesting depth `depth` (0-based), cycling through the set.
---@param charset? "unicode"|"ascii"
---@param depth integer
---@return string
function M.bullet(charset, depth)
  local bullets = M.glyphs(charset).bullets
  return bullets[(depth % #bullets) + 1]
end

-- Horizontal border for columns with content widths `widths` (each column
-- also gets one space of padding on both sides).
---@param widths integer[]
---@param position "top"|"header"|"row"|"bottom"
---@param charset? "unicode"|"ascii"
---@return string
function M.rule(widths, position, charset)
  local g = M.glyphs(charset)
  local set = g[POSITIONS[position]]
  local parts = {}
  for i, w in ipairs(widths) do
    parts[i] = g.h:rep(w + 2)
  end
  return set[1] .. table.concat(parts, set[2]) .. set[3]
end

return M
