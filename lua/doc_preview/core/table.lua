-- Table layout: column fitting, cell wrap, row and grid layout
-- (doc/architecture.md 3, 4.1). Pure functions, no Neovim API beyond core.text.
-- The fitting algorithm is original work.
local text = require("doc_preview.core.text")
local box = require("doc_preview.core.box")

local M = {}

local FLOOR_CAP = 8

local function sum(list)
  local total = 0
  for _, w in ipairs(list) do
    total = total + w
  end
  return total
end

-- Per-column floors; all 1 when the floors alone do not fit.
local function column_floors(natural, minimums, available)
  local floors = {}
  for i, w in ipairs(natural) do
    floors[i] = math.max(1, math.min(minimums[i] or 1, w))
  end
  if sum(floors) > available then
    for i = 1, #natural do
      floors[i] = 1
    end
  end
  return floors, sum(floors)
end

-- Floors plus proportional share of `extra`; fractions for the remainder.
local function shrink(natural, floors, extra, demand)
  local widths, fracs = {}, {}
  for i, w in ipairs(natural) do
    local part = extra * (w - floors[i])
    widths[i] = floors[i] + math.floor(part / demand)
    fracs[i] = { i = i, r = part % demand }
  end
  table.sort(fracs, function(a, b)
    return a.r ~= b.r and a.r > b.r or a.r == b.r and a.i < b.i
  end)
  return widths, fracs
end

-- Hand the leftover columns out by largest fraction.
local function distribute(widths, floors, fracs, extra)
  local left = extra
  for i = 1, #widths do
    left = left - (widths[i] - floors[i])
  end
  for k = 1, left do
    widths[fracs[k].i] = widths[fracs[k].i] + 1
  end
end

-- Column widths for `natural` widths in `available` columns (borders and
-- padding already subtracted). Natural when they fit, else proportional
-- shrink above the floors, remainder by largest fraction. Returns nil when
-- even width 1 per column does not fit. The sum never exceeds `available`.
---@param natural integer[]
---@param available integer
---@param minimums integer[]
---@return integer[]|nil
function M.fit(natural, available, minimums)
  local n, total = #natural, sum(natural)
  if total <= available then
    return { unpack(natural) }
  end
  if available < n then
    return nil
  end
  local floors, floor_sum = column_floors(natural, minimums, available)
  local widths, fracs = shrink(natural, floors, available - floor_sum, total - floor_sum)
  distribute(widths, floors, fracs, available - floor_sum)
  return widths
end

-- Floor for a column: its longest word (capped), at least the widest character.
---@param texts string[]
---@return integer floor
---@return integer widest  widest single character
function M.minimum(texts)
  local word, char = 1, 1
  for _, s in ipairs(texts) do
    for w in s:gmatch("%S+") do
      word = math.max(word, text.width(w))
    end
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      char = math.max(char, text.width(ch))
    end
  end
  return math.max(math.min(word, FLOOR_CAP), char), char
end

-- Wrap one cell to `width`; always at least one (possibly empty) line.
-- Spans: { line, col_start, col_end, hl_group }, line 1-based.
---@param s string
---@param width integer
---@param ranges? table[]  { from, to, group } 0-based byte offsets in `s`
---@return string[] lines
---@return table[] spans
function M.wrap_cell(s, width, ranges)
  local lines, spans = text.wrap_styled(s, width, ranges or {})
  if #lines == 0 then
    lines = { "" }
  end
  return lines, spans
end

-- One grid row as output lines. `cells` are { text, ranges? }; `align` is a
-- per-column list (nil entry = left). Spans are per output line, byte columns
-- relative to the whole line: { line, col_start, col_end, hl_group }.
---@param cells table[]
---@param widths integer[]
---@param align table
---@param charset? string
---@return string[] lines
---@return table[] spans
function M.layout_row(cells, widths, align, charset)
  local v = box.glyphs(charset).v
  local wrapped, height = {}, 1
  for i, cell in ipairs(cells) do
    local lines, spans = M.wrap_cell(cell.text, widths[i], cell.ranges)
    wrapped[i] = { lines = lines, spans = spans }
    height = math.max(height, #lines)
  end
  local out, all_spans = {}, {}
  for k = 1, height do
    local parts, pos = { v }, #v
    for i, w in ipairs(widths) do
      local line = wrapped[i].lines[k] or ""
      local padded = text.pad(line, w, align[i])
      local lead = line == "" and 0 or #padded:match("^ *")
      for _, sp in ipairs(wrapped[i].spans) do
        if sp.line == k then
          local c = pos + 1 + lead
          all_spans[#all_spans + 1] = {
            line = k,
            col_start = c + sp.col_start,
            col_end = c + sp.col_end,
            hl_group = sp.hl_group,
          }
        end
      end
      parts[#parts + 1] = " " .. padded .. " " .. v
      pos = pos + #parts[#parts]
    end
    out[k] = table.concat(parts)
  end
  return out, all_spans
end

local function columns(grid, n)
  local natural, minimums, chars = {}, {}, {}
  for c = 1, n do
    local texts, widest = {}, 1
    for r, row in ipairs(grid) do
      texts[r] = row[c].text
      for line in (texts[r] .. "\n"):gmatch("([^\n]*)\n") do
        widest = math.max(widest, text.width((line:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))))
      end
    end
    natural[c] = widest
    minimums[c], chars[c] = M.minimum(texts)
  end
  return natural, minimums, chars
end

-- Degenerate width: plain pipe rows, hard-wrapped to `width`.
local function fallback(grid, width, charset)
  local v = box.glyphs(charset).v
  local items = {}
  for r, row in ipairs(grid) do
    local texts = {}
    for c, cell in ipairs(row) do
      texts[c] = cell.text:gsub("%s+", " ")
    end
    for _, line in ipairs(text.hard_wrap(v .. table.concat(texts, v) .. v, width)) do
      items[#items + 1] = { text = line, row = r, spans = {} }
    end
  end
  return items
end

-- Whole grid as output items { text, row?, rule?, spans } in order. `grid` is
-- a list of rows (header first), every row a list of { text, ranges? }.
-- `row` is the grid row index; `rule` the border position ("top", "header",
-- "bottom"); spans carry `line` = 1 and byte columns of that item.
---@param grid table[]
---@param align table
---@param width integer
---@param charset? string
---@return table[]
function M.layout(grid, align, width, charset)
  local n = #grid[1]
  local natural, minimums, chars = columns(grid, n)
  local widths = M.fit(natural, width - (n + 1) - 2 * n, minimums)
  if width < 3 * n + 1 or not widths then
    return fallback(grid, width, charset)
  end
  for c, w in ipairs(widths) do
    if chars[c] > w then
      return fallback(grid, width, charset)
    end
  end
  local items = { { text = box.rule(widths, "top", charset), rule = "top", spans = {} } }
  for r, row in ipairs(grid) do
    local lines, spans = M.layout_row(row, widths, align, charset)
    for k, line in ipairs(lines) do
      local mine = {}
      for _, sp in ipairs(spans) do
        if sp.line == k then
          mine[#mine + 1] = sp
        end
      end
      items[#items + 1] = { text = line, row = r, spans = mine }
    end
    if r == 1 then
      items[#items + 1] =
        { text = box.rule(widths, "header", charset), rule = "header", spans = {} }
    end
  end
  items[#items + 1] = { text = box.rule(widths, "bottom", charset), rule = "bottom", spans = {} }
  return items
end

return M
