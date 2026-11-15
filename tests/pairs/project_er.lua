-- Facts projection for ER diagram pairs (doc/testing.md 3.2): a parsed ER
-- Graph as plain lines, one fact per line.
--   direction LR
--   entity A "Label"
--     attr string name keys=PK,FK "comment"     (keys and comment optional)
--   relationship A B identifying tail=one head=zero_many "label"
local M = {}

local function quote(s)
  return '"' .. s:gsub("\n", "\\n") .. '"'
end

local function attr(a)
  local line = ("  attr %s %s"):format(a.type, a.name)
  line = line .. (#a.keys > 0 and (" keys=" .. table.concat(a.keys, ",")) or "")
  return a.comment and (line .. " " .. quote(a.comment)) or line
end

local function relationship(e)
  local line = ("relationship %s %s %s tail=%s head=%s"):format(
    e.from,
    e.to,
    e.identifying and "identifying" or "non-identifying",
    e.tail_kind,
    e.head_kind
  )
  return e.label and (line .. " " .. quote(e.label)) or line
end

---@param g table  graph from er.parse
---@return string
function M.project(g)
  local out = { "direction " .. g.direction }
  for _, n in ipairs(g.nodes) do
    out[#out + 1] = ("entity %s %s"):format(n.id, quote(n.label))
    for _, a in ipairs(g.entities[n.id].attrs) do
      out[#out + 1] = attr(a)
    end
  end
  for _, e in ipairs(g.edges) do
    out[#out + 1] = relationship(e)
  end
  return table.concat(out, "\n")
end

return M
