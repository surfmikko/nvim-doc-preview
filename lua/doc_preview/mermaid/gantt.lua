-- Mermaid gantt chart: parse and schedule (doc/diagram-model.md 1). Shares
-- nothing with graph/. Parse result:
--   { title?, date_format, format_note?, axis_format?, tick_interval?,
--     today_marker?, excludes?, includes?, unit = "day"|"minute",
--     sections = { name... },
--     tasks = { { section, section_no, title, tags, id?, milestone, line, start, finish } } }
-- `start`/`finish` are resolved (finish exclusive, so `2024-01-01, 3d` ends
-- 2024-01-04) in the model's unit: days since 1970-01-01, or minutes when
-- any moment is not at midnight. A task before the first `section` has
-- `section = ""`, `section_no = 0` (index into `sections`). A task without start follows the previous task's finish;
-- `after a b` starts at the later finish; `until a` ends at the start of a.
-- `axisFormat`, `tickInterval`, `todayMarker`, `excludes` and `includes` are
-- kept verbatim and not applied; `weekday`, `weekend`, `inclusiveEndDates`,
-- `topAxis`, `click`, `accTitle`, `accDescr` are ignored.
-- Drawing is in gantt_draw.lua; `render` boxes the source when too narrow.
local dates = require("doc_preview.mermaid.gantt_dates")
local draw = require("doc_preview.mermaid.gantt_draw")
local errbox = require("doc_preview.core.errbox")
local source = require("doc_preview.mermaid.source")
local syntax = require("doc_preview.mermaid.gantt_syntax")

local M = {}

local DEFAULT_FORMAT = "YYYY-MM-DD"
local SETTINGS = {
  axisFormat = "axis_format",
  tickInterval = "tick_interval",
  todayMarker = "today_marker",
  excludes = "excludes",
  includes = "includes",
}
local IGNORED = {
  weekday = true,
  weekend = true,
  inclusiveEndDates = true,
  topAxis = true,
  click = true,
  accTitle = true,
  accDescr = true,
}

local function fail(lnum, msg)
  error(("line %d: %s"):format(lnum, msg), 0)
end

local function set_date_format(g, fmt)
  local parts = dates.compile(fmt)
  if parts then
    g.date_format, g.parts, g.format_note = fmt, parts, nil
  else
    g.date_format, g.parts = DEFAULT_FORMAT, dates.compile(DEFAULT_FORMAT)
    g.format_note = ("dateFormat %s is not supported, using %s"):format(fmt, DEFAULT_FORMAT)
  end
end

local function add_task(g, stmt, lnum)
  local t, err = syntax.task(stmt)
  if not t then
    fail(lnum, err)
  end
  t.section, t.section_no, t.line = g.section, #g.sections, lnum
  t.milestone = vim.tbl_contains(t.tags, "milestone")
  if t.id and g.by_id[t.id] then
    fail(lnum, "duplicate task id " .. t.id)
  end
  g.tasks[#g.tasks + 1] = t
  if t.id then
    g.by_id[t.id] = t
  end
end

local function parse_statement(g, stmt, lnum)
  local word, rest = stmt:match("^(%S+)%s*(.-)$")
  if word == "title" then
    g.title = rest ~= "" and rest or nil
  elseif word == "dateFormat" then
    set_date_format(g, rest)
  elseif SETTINGS[word] then
    g[SETTINGS[word]] = rest
  elseif word == "section" then
    g.sections[#g.sections + 1] = rest
    g.section = rest
  elseif not IGNORED[word] then
    add_task(g, stmt, lnum)
  end
end

local function known(g, t, id)
  return g.by_id[id] or fail(t.line, "unknown task id " .. id)
end

-- Start of `t` in minutes; `visit(other)` resolves another task first.
local function start_of(g, t, prev, visit)
  local s = t.raw_start
  if s == nil then
    if not prev then
      fail(t.line, "task has no start and no previous task")
    end
    return visit(prev).finish
  end
  local ids = s:match("^after%s+(.+)$")
  if not ids then
    return dates.parse(g.parts, s) or fail(t.line, "bad date " .. s)
  end
  local latest = -math.huge
  for id in ids:gmatch("%S+") do
    latest = math.max(latest, visit(known(g, t, id)).finish)
  end
  return latest
end

local function finish_of(g, t, visit)
  local f = t.raw_finish
  if f == nil then
    if t.milestone then
      return t.start
    end
    fail(t.line, "task has no end date or duration")
  end
  local id = f:match("^until%s+(%S+)$")
  if id then
    return visit(known(g, t, id)).start
  end
  local d = dates.duration(f)
  if d then
    return t.start + d
  end
  return dates.parse(g.parts, f) or fail(t.line, "bad date " .. f)
end

local function resolve(g, t, prev, run)
  local function visit(other)
    if other.state == "visiting" then
      fail(t.line, "cycle in task dependencies at " .. (other.id or other.title))
    end
    if other.state ~= "done" then
      run(other)
    end
    return other
  end
  t.state = "visiting"
  t.start = start_of(g, t, prev, visit)
  t.finish = finish_of(g, t, visit)
  t.state = "done"
end

local function resolve_all(g)
  local index = {}
  for i, t in ipairs(g.tasks) do
    index[t] = i
    t.raw_start, t.raw_finish = t.start, t.finish
    t.start, t.finish = nil, nil
  end
  local function run(t)
    resolve(g, t, g.tasks[index[t] - 1], run)
  end
  for _, t in ipairs(g.tasks) do
    if t.state ~= "done" then
      run(t)
    end
  end
end

-- Day units when every moment sits at midnight, else minutes.
local function convert_units(g)
  g.unit = "day"
  for _, t in ipairs(g.tasks) do
    if t.start % dates.DAY ~= 0 or t.finish % dates.DAY ~= 0 then
      g.unit = "minute"
    end
  end
  for _, t in ipairs(g.tasks) do
    if g.unit == "day" then
      t.start, t.finish = t.start / dates.DAY, t.finish / dates.DAY
    end
    t.state, t.raw_start, t.raw_finish = nil, nil, nil
  end
end

-- Parse and schedule; raises a plain string naming the line on an error.
---@param lines string[]
---@return table gantt
function M.parse(lines)
  local g = { sections = {}, tasks = {}, by_id = {}, section = "" }
  set_date_format(g, DEFAULT_FORMAT)
  local seen = false
  for i = source.first_content(lines), #lines do
    local stmt = lines[i]:match("^%s*(.-)%s*$")
    if stmt ~= "" and not stmt:match("^%%%%") then
      if seen then
        parse_statement(g, stmt, i)
      elseif stmt == "gantt" then
        seen = true
      else
        fail(i, "expected gantt")
      end
    end
  end
  resolve_all(g)
  convert_units(g)
  g.parts, g.by_id, g.section = nil, nil, nil
  return g
end

---@param lines string[]
---@param ctx { width: integer, charset?: string }
---@return doc_preview.Output
function M.render(lines, ctx)
  local g = M.parse(lines)
  if #g.tasks == 0 then
    error("no tasks", 0)
  end
  return draw.draw(g, ctx)
    or errbox.render(lines, ctx, ("diagram wider than %d columns"):format(ctx.width))
end

return M
