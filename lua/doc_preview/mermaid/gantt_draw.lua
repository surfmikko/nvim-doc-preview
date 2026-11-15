-- Drawing of a parsed gantt chart (doc/diagram-model.md 1): optional title,
-- a tick row with dates, then per section a header row and one bar row per
-- task: label column, gap (`!` marks a crit task), bar area. The span of all
-- tasks is mapped onto the bar area with x(t) = floor((t - first) * W / span);
-- W is the bar area width (a whole multiple of the span when it is smaller,
-- so one unit is then `W / span` columns). Never wider than ctx.width.
local canvas = require("doc_preview.core.canvas")
local dates = require("doc_preview.mermaid.gantt_dates")
local job = require("doc_preview.core.job")
local text = require("doc_preview.core.text")

local M = {}

local LABEL, BAR, BORDER =
  "DocPreviewDiagramLabel", "DocPreviewDiagramEdge", "DocPreviewDiagramBorder"
local PREFERRED_BAR, MIN_BAR, MIN_LABEL = 20, 10, 4
local BATCH = 20
-- Tick intervals in minutes, smallest first.
local INTERVALS =
  { 1, 5, 15, 30, 60, 180, 360, 720, 1440, 2880, 10080, 20160, 43200, 131040, 262080, 525600 }

local GLYPHS = {
  unicode = { done = "█", active = "▓", plain = "░", milestone = "◆" },
  ascii = { done = "#", active = "=", plain = "-", milestone = "*" },
}

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

-- Label and bar area widths for `width`, or nil when they do not fit.
local function columns(g, width)
  local natural = 1
  for _, t in ipairs(g.tasks) do
    natural = math.max(natural, text.width(t.title))
  end
  local lw = math.min(natural, width - 1 - PREFERRED_BAR)
  if lw < math.min(natural, MIN_LABEL + 2) then
    lw = math.min(natural, width - 1 - MIN_BAR)
  end
  if lw < math.min(natural, MIN_LABEL) then
    return nil
  end
  return lw, width - lw - 1
end

-- Column mapping: first moment, span in units and bar area width.
local function scale(g, bw)
  local first, last = math.huge, -math.huge
  for _, t in ipairs(g.tasks) do
    first = math.min(first, t.start)
    last = math.max(last, t.finish)
  end
  local span = math.max(last - first, 1)
  local w = span <= bw and span * math.floor(bw / span) or bw
  return { first = first, span = span, w = w }
end

local function column(sc, t)
  return math.floor((t - sc.first) * sc.w / sc.span)
end

-- Bar cells [x0, x1) of a task; a milestone or a sub-column task takes one.
function M.cells(sc, t)
  local x0 = math.min(column(sc, t.start), sc.w - 1)
  local x1 = math.max(math.min(column(sc, t.finish), sc.w), x0 + 1)
  return x0, x1
end

local function tick_format(g, sc)
  local per = g.unit == "day" and dates.DAY or 1
  local minutes = sc.span * per
  if g.unit == "day" then
    return minutes > 365 * dates.DAY and "%04d-%02d" or "%02d-%02d", per
  end
  return minutes > dates.DAY and "%02d-%02d %02d:%02d" or "%02d:%02d", per
end

local function tick_label(fmt, g, minute)
  local y, mo, d, h, mi = dates.from_minutes(minute)
  if g.unit == "day" then
    return fmt:find("%04d", 1, true) and fmt:format(y, mo) or fmt:format(mo, d)
  end
  return fmt:find("%%02d%-") and fmt:format(mo, d, h, mi) or fmt:format(h, mi)
end

-- Tick row: dates at the smallest interval whose labels do not touch.
local function ticks(c, g, sc, x0, y)
  local fmt, per = tick_format(g, sc)
  local lw = #tick_label(fmt, g, 0)
  for _, interval in ipairs(INTERVALS) do
    local units = interval / per
    if units >= 1 and units * sc.w / sc.span >= lw + 1 then
      local t = sc.first
      while t < sc.first + sc.span do
        local x = column(sc, t)
        if x + lw <= sc.w then
          c:put(x0 + x, y, tick_label(fmt, g, t * per), LABEL)
        end
        t = t + units
      end
      return
    end
  end
  if sc.w >= lw then
    c:put(x0, y, tick_label(fmt, g, sc.first * per), LABEL)
  end
end

local function bar_glyph(t, glyphs)
  if t.milestone then
    return glyphs.milestone
  end
  local tags = t.tags
  return glyphs[vim.tbl_contains(tags, "done") and "done" or vim.tbl_contains(tags, "active") and "active" or "plain"]
end

local function task_row(c, t, lw, sc, y)
  local glyphs = GLYPHS[c.charset] or GLYPHS.unicode
  c:put(0, y, text.pad(fit(t.title, lw), lw), LABEL)
  if vim.tbl_contains(t.tags, "crit") then
    c:put(lw, y, "!", BORDER)
  end
  local x0, x1 = M.cells(sc, t)
  local glyph = bar_glyph(t, glyphs)
  if t.milestone then
    x1 = x0 + 1
  end
  c:put(lw + 1 + x0, y, glyph:rep(x1 - x0), BAR)
end

local function rows(g)
  local list = {}
  for no = 0, #g.sections do
    if no > 0 then
      list[#list + 1] = { header = g.sections[no] }
    end
    for _, t in ipairs(g.tasks) do
      if t.section_no == no then
        list[#list + 1] = { task = t }
      end
    end
  end
  return list
end

---@param g table parsed gantt with at least one task
---@param ctx { width: integer, charset?: string }
---@return doc_preview.Output|nil  nil when the width is too small
function M.draw(g, ctx)
  local lw, bw = columns(g, ctx.width)
  if not lw then
    return nil
  end
  local sc = scale(g, bw)
  local list = rows(g)
  local top = g.title and 1 or 0
  local c = canvas.new(ctx.width, top + 1 + #list, ctx.charset)
  if g.title then
    c:put(0, 0, fit(g.title, ctx.width), LABEL)
  end
  ticks(c, g, sc, lw + 1, top)
  for i, r in ipairs(list) do
    local y = top + i
    if r.header then
      c:put(0, y, fit(r.header, ctx.width), BORDER)
    else
      task_row(c, r.task, lw, sc, y)
    end
    if i % BATCH == 0 then
      job.yield_point()
    end
  end
  return c:to_output()
end

return M
