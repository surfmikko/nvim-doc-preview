-- Mermaid pie chart (doc/diagram-model.md 1). Shares nothing with graph/.
-- Parse result: `{ title?, show_data, slices = { { label, value, raw, pct } } }`
-- with integer percentages summing to 100 (largest remainder; all 0 when the
-- total is 0). Drawn as one horizontal bar per slice in source order.
local canvas = require("doc_preview.core.canvas")
local errbox = require("doc_preview.core.errbox")
local source = require("doc_preview.mermaid.source")
local text = require("doc_preview.core.text")

local M = {}

local LABEL, BAR = "DocPreviewDiagramLabel", "DocPreviewDiagramEdge"
local MAX_BAR, MIN_BAR, MIN_LABEL = 30, 8, 4
local PARTIAL = { "▏", "▎", "▍", "▌", "▋", "▊", "▉" }

local function fail(lnum, msg)
  error(("line %d: %s"):format(lnum, msg), 0)
end

local function number(raw, lnum)
  if raw:match("^%-") then
    fail(lnum, "negative value " .. raw)
  end
  if not (raw:match("^%d+%.?%d*$") or raw:match("^%.%d+$")) then
    fail(lnum, "invalid value " .. raw)
  end
  return tonumber(raw)
end

-- Percentages as integers summing to 100 by largest remainder.
---@param slices table[]
function M.percentages(slices)
  local total, sum, order = 0, 0, {}
  for _, s in ipairs(slices) do
    total = total + s.value
  end
  for i, s in ipairs(slices) do
    local exact = total > 0 and s.value * 100 / total or 0
    s.pct = math.floor(exact + 1e-9)
    s.frac = exact - s.pct
    sum = sum + s.pct
    order[i] = i
  end
  table.sort(order, function(a, b)
    local fa, fb = slices[a].frac, slices[b].frac
    if fa ~= fb then
      return fa > fb
    end
    return a < b
  end)
  for k = 1, total > 0 and math.max(100 - sum, 0) or 0 do
    local s = slices[order[(k - 1) % #order + 1]]
    s.pct = s.pct + 1
  end
  for _, s in ipairs(slices) do
    s.frac = nil
  end
end

-- `pie [showData] [title X]` header remainder; returns show_data, title.
local function header(rest, lnum)
  local show, title
  rest = rest:match("^%s*(.-)%s*$")
  if rest:match("^showData") then
    show = true
    rest = rest:sub(9):match("^%s*(.-)$")
  end
  if rest:match("^title%f[%s%z]") then
    title = rest:sub(6):match("^%s*(.-)$")
  elseif rest ~= "" then
    fail(lnum, "syntax error: " .. rest)
  end
  return show or false, title
end

local function statement(pie, stmt, lnum)
  if stmt == "showData" then
    pie.show_data = true
  elseif stmt:match("^title%f[%s%z]") then
    pie.title = stmt:sub(6):match("^%s*(.-)$")
  else
    local label, raw = stmt:match('^"([^"]*)"%s*:%s*(.-)%s*;?$')
    if not label then
      fail(lnum, "syntax error: " .. stmt)
    end
    local slices = pie.slices
    slices[#slices + 1] = { label = label, value = number(raw, lnum), raw = raw }
  end
end

-- Parse the source into a pie model; raises a plain string on a syntax error.
---@param lines string[]
---@return table pie
function M.parse(lines)
  local pie
  for i = source.first_content(lines), #lines do
    local stmt = lines[i]:match("^%s*(.-)%s*$")
    if stmt ~= "" and not stmt:match("^%%%%") then
      if not pie then
        local rest = stmt:match("^pie(.*)$")
        if not rest or (rest ~= "" and not rest:match("^%s")) then
          fail(i, "expected pie")
        end
        pie = { slices = {} }
        pie.show_data, pie.title = header(rest, i)
      else
        statement(pie, stmt, i)
      end
    end
  end
  pie = pie or { show_data = false, slices = {} }
  M.percentages(pie.slices)
  return pie
end

-- Longest prefix of `s` that fits in `max` columns; "..." marks a cut.
local function fit(s, max)
  if text.width(s) <= max then
    return s
  end
  local dots = math.min(max, 3)
  local cut = ""
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if text.width(cut .. ch) > max - dots then
      break
    end
    cut = cut .. ch
  end
  return cut .. ("."):rep(dots)
end

-- Bar for `pct` percent of `bw` cells.
local function bar(pct, bw, charset)
  if charset == "ascii" then
    return ("#"):rep(math.floor(pct * bw / 100 + 0.5))
  end
  local eighths = math.floor(pct * bw * 8 / 100 + 0.5)
  if pct > 0 then
    eighths = math.max(eighths, 1)
  end
  return ("█"):rep(math.floor(eighths / 8)) .. (PARTIAL[eighths % 8] or "")
end

-- Column widths for `width`, or nil when the minimum does not fit.
local function columns(pie, width)
  local lw, vw = 0, 0
  for _, s in ipairs(pie.slices) do
    lw = math.max(lw, text.width(s.label))
    vw = math.max(vw, #s.raw)
  end
  local rest = 2 + 4 + (pie.show_data and vw + 1 or 0) -- gaps, "100%", value
  local bw = math.min(MAX_BAR, width - rest - lw)
  if bw < MIN_BAR then
    bw = MIN_BAR
    lw = width - rest - bw
    if lw < MIN_LABEL then
      return nil
    end
  end
  return { label = lw, bar = bw, value = vw }
end

local function draw(pie, col, ctx)
  local top = pie.title and 1 or 0
  local c = canvas.new(ctx.width, top + #pie.slices, ctx.charset)
  if pie.title then
    c:put(0, 0, fit(pie.title, ctx.width), LABEL)
  end
  for i, s in ipairs(pie.slices) do
    local y = top + i - 1
    local bx = col.label + 1
    c:put(0, y, text.pad(fit(s.label, col.label), col.label), LABEL)
    c:put(bx, y, bar(s.pct, col.bar, ctx.charset), BAR)
    local px = bx + col.bar + 1
    c:put(px, y, text.pad(s.pct .. "%", 4, "right"))
    if pie.show_data then
      c:put(px + 5, y, text.pad(s.raw, col.value, "right"))
    end
  end
  return c:to_output()
end

---@param lines string[]
---@param ctx { width: integer, charset?: string }
---@return doc_preview.Output
function M.render(lines, ctx)
  local pie = M.parse(lines)
  if #pie.slices == 0 then
    error("no slices", 0)
  end
  local col = columns(pie, ctx.width)
  if not col then
    return errbox.render(lines, ctx, ("diagram wider than %d columns"):format(ctx.width))
  end
  return draw(pie, col, ctx)
end

return M
