-- Gantt task-line tokens: `Title :tags, id, start, end` (parsing only; dates
-- are read later by gantt.lua once `dateFormat` is known).
local dates = require("doc_preview.mermaid.gantt_dates")

local M = {}

local TAGS = { done = true, active = true, crit = true, milestone = true }

local function is_id(p)
  return p:match("^[%w_%-]+$") ~= nil
end

local function is_duration(p)
  return dates.duration(p) ~= nil
end

local function is_until(p)
  return p:match("^until%s+%S") ~= nil
end

local function is_after(p)
  return p:match("^after%s+%S") ~= nil
end

-- A bare word is an id, not a date or duration; dates start with a digit.
local function is_bare_id(p)
  return is_id(p) and not p:match("^%d") and not is_duration(p) and p ~= "after" and p ~= "until"
end

-- Merge `after a` plus following bare ids (`after a, b, 3d`) into one part.
local function merge_after(parts)
  local out, i = {}, 1
  while i <= #parts do
    local p = parts[i]
    i = i + 1
    if is_after(p) then
      while parts[i] and is_bare_id(parts[i]) do
        p = p .. " " .. parts[i]
        i = i + 1
      end
    end
    out[#out + 1] = p
  end
  return out
end

local function split(s)
  local parts = {}
  for p in (s .. ","):gmatch("%s*(.-)%s*,") do
    parts[#parts + 1] = p
  end
  return parts
end

local function check_parts(parts, stmt)
  for _, p in ipairs(parts) do
    if p == "" then
      return "empty field in task: " .. stmt
    end
  end
  if #parts > 3 then
    return "too many fields in task: " .. stmt
  end
end

-- Take the leading id off `parts` into `t` when there is one; error message on a bad id.
local function take_id(t, parts)
  if #parts == 3 or (#parts == 2 and is_bare_id(parts[1])) then
    t.id = table.remove(parts, 1)
    if not is_bare_id(t.id) then
      return "invalid task id " .. t.id
    end
  end
end

-- Raw spec: `{ title, tags = {...}, id?, start?, finish? }`; start and finish
-- are strings (`after a b`, `until a`, a date or a duration). Returns nil and
-- a message on a malformed line.
---@param stmt string
---@return table|nil, string?
function M.task(stmt)
  local title, data = stmt:match("^(.-)%s*:%s*(.*)$")
  if not title or title == "" then
    return nil, "syntax error: " .. stmt
  end
  local t = { title = title, tags = {} }
  local parts = merge_after(split(data))
  while parts[1] and TAGS[parts[1]] do
    t.tags[#t.tags + 1] = table.remove(parts, 1)
  end
  local err = check_parts(parts, stmt) or take_id(t, parts)
  if err then
    return nil, err
  end
  t.finish = table.remove(parts)
  t.start = table.remove(parts)
  return t
end

M.is_until = is_until
M.is_after = is_after

return M
