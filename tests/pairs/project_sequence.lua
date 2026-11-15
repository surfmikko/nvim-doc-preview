-- Facts projection for sequence diagram pairs (doc/testing.md 3.2): a parsed
-- Seq as plain lines, one fact per line, blocks indented two spaces per level.
--   participant A actor "Alice"
--   message A B dashed arrow "text" activate deactivate   (flags optional)
--   note over A,B "text"
--   activate A / deactivate A
--   autonumber [off] [start=N] [step=N]
--   block loop "label"
--     section "label"        (later sections only, label optional)
--   (a block's events are indented under it; no closing line)
local M = {}

local function quote(s)
  return '"' .. s:gsub("\n", "\\n") .. '"'
end

local function message(e)
  local line = ("message %s %s %s %s %s"):format(e.from, e.to, e.line, e.head, quote(e.text))
  return line .. (e.activate and " activate" or "") .. (e.deactivate and " deactivate" or "")
end

local function autonumber(e)
  local line = "autonumber" .. (e.off and " off" or "")
  line = line .. (e.start and (" start=" .. e.start) or "")
  return line .. (e.step and (" step=" .. e.step) or "")
end

local function simple(e)
  if e.kind == "message" then
    return message(e)
  elseif e.kind == "note" then
    return ("note %s %s %s"):format(e.side, table.concat(e.targets, ","), quote(e.text))
  elseif e.kind == "autonumber" then
    return autonumber(e)
  end
  return e.kind .. " " .. e.id
end

local project_events

local function block(out, e, depth)
  local pad = ("  "):rep(depth)
  out[#out + 1] = ("%sblock %s %s"):format(pad, e.type, quote(e.label))
  for i, sec in ipairs(e.sections) do
    if i > 1 then
      out[#out + 1] = ("%s  section %s"):format(pad, quote(sec.label))
    end
    project_events(out, sec.events, depth + 1)
  end
end

function project_events(out, events, depth)
  for _, e in ipairs(events) do
    if e.kind == "block" then
      block(out, e, depth)
    else
      out[#out + 1] = ("  "):rep(depth) .. simple(e)
    end
  end
end

---@param seq table  from sequence.parse
---@return string
function M.project(seq)
  local out = {}
  for _, p in ipairs(seq.participants) do
    out[#out + 1] = ("participant %s %s %s"):format(p.id, p.kind, quote(p.label))
  end
  project_events(out, seq.events, 0)
  return table.concat(out, "\n")
end

return M
