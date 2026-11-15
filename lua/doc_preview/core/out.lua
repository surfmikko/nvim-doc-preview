-- Output builder: lines, highlight spans, source map (doc/architecture.md 4.1).
local text_mod = require("doc_preview.core.text")

local M = {}

local Out = {}
Out.__index = Out

---@return doc_preview.Output
function M.new()
  return setmetatable({ lines = {}, spans = {}, map = {} }, Out)
end

---@param text string
---@return integer line  1-based index of the added line
function Out:add_line(text)
  self.lines[#self.lines + 1] = text
  return #self.lines
end

function Out:add_span(line, col_start, col_end, hl_group)
  self.spans[#self.spans + 1] =
    { line = line, col_start = col_start, col_end = col_end, hl_group = hl_group }
end

function Out:add_map(out_start, out_end, src_start, src_end)
  self.map[#self.map + 1] =
    { out_start = out_start, out_end = out_end, src_start = src_start, src_end = src_end }
end

-- Append another Output below this one, rebasing its line numbers.
function Out:append(frag)
  local offset = #self.lines
  for _, text in ipairs(frag.lines) do
    self:add_line(text)
  end
  for _, s in ipairs(frag.spans) do
    self:add_span(s.line + offset, s.col_start, s.col_end, s.hl_group)
  end
  for _, m in ipairs(frag.map) do
    self:add_map(m.out_start + offset, m.out_end + offset, m.src_start, m.src_end)
  end
end

-- New fragment: `frag` with `str` prepended to every line (blank ones too).
-- Spans shift right by #str, map entries are kept, and `group` (optional)
-- styles the prefix on every line.
function M.prefix(frag, str, group)
  local result = M.new()
  for i, line in ipairs(frag.lines) do
    result:add_line(str .. line)
    if group and #str > 0 then
      result:add_span(i, 0, #str, group)
    end
  end
  for _, s in ipairs(frag.spans) do
    result:add_span(s.line, s.col_start + #str, s.col_end + #str, s.hl_group)
  end
  for _, m in ipairs(frag.map) do
    result:add_map(m.out_start, m.out_end, m.src_start, m.src_end)
  end
  return result
end

-- True when `o` has the Output shape and no line is wider than `width`
-- (engine results are checked with this before they enter a document).
function M.valid(o, width)
  if type(o) ~= "table" or type(o.lines) ~= "table" then
    return false
  end
  if type(o.spans) ~= "table" or type(o.map) ~= "table" then
    return false
  end
  for _, l in ipairs(o.lines) do
    if type(l) ~= "string" or text_mod.width(l) > width then
      return false
    end
  end
  return true
end

-- Map `line` from one side of the source map to the other. `a`/`b` name the
-- field prefixes ("src"/"out"). Inside an entry the position is linearly
-- interpolated (identity for equal sizes); outside any entry it snaps to the
-- nearest entry's edge.
local function interpolate(m, line, a, b)
  local lo, hi = m[a .. "_start"], m[a .. "_end"]
  local blo, bhi = m[b .. "_start"], m[b .. "_end"]
  if hi == lo then
    return blo
  end
  return blo + math.ceil((line - lo) * (bhi - blo) / (hi - lo))
end

local function snap(m, line, a, b)
  return line < m[a .. "_start"] and m[b .. "_start"] or m[b .. "_end"]
end

local function translate(map, line, a, b)
  local best, best_dist
  for _, m in ipairs(map) do
    local lo, hi = m[a .. "_start"], m[a .. "_end"]
    if line >= lo and line <= hi then
      return interpolate(m, line, a, b)
    end
    local dist = line < lo and lo - line or line - hi
    if not best_dist or dist < best_dist then
      best, best_dist = m, dist
    end
  end
  return best and snap(best, line, a, b)
end

---@param line integer 1-based source line
---@return integer|nil out_line  nil when the map is empty
function Out:src_to_out(line)
  return translate(self.map, line, "src", "out")
end

---@param line integer 1-based output line
---@return integer|nil src_line  nil when the map is empty
function Out:out_to_src(line)
  return translate(self.map, line, "out", "src")
end

return M
