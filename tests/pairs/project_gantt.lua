-- Facts projection for gantt pairs (doc/testing.md 3.2): a parsed and
-- scheduled gantt as plain lines, one fact per line.
--   gantt unit=day format=YYYY-MM-DD title "Plan"
--   note dateFormat ... is not supported, ...        (only with a fallback)
--   section "Phase"
--   task "Title" id=a tags=done,crit start=2024-01-01 end=2024-01-04
local dates = require("doc_preview.mermaid.gantt_dates")

local M = {}

local function quote(s)
  return '"' .. s .. '"'
end

local function when(g, v)
  return dates.format(g.unit == "day" and v * dates.DAY or v, g.unit)
end

local function task(g, t)
  local line = "task " .. quote(t.title)
  line = line .. (t.id and (" id=" .. t.id) or "")
  line = line .. (#t.tags > 0 and (" tags=" .. table.concat(t.tags, ",")) or "")
  return ("%s start=%s end=%s"):format(line, when(g, t.start), when(g, t.finish))
end

---@param g table  from gantt.parse
---@return string
function M.project(g)
  local head = ("gantt unit=%s format=%s"):format(g.unit, g.date_format)
  local out = { g.title and (head .. " title " .. quote(g.title)) or head }
  if g.format_note then
    out[#out + 1] = "note " .. g.format_note
  end
  local n = 0
  local function sections_up_to(upto)
    while n < upto do
      n = n + 1
      out[#out + 1] = "section " .. quote(g.sections[n])
    end
  end
  for _, t in ipairs(g.tasks) do
    sections_up_to(t.section_no)
    out[#out + 1] = task(g, t)
  end
  sections_up_to(#g.sections)
  return table.concat(out, "\n")
end

return M
