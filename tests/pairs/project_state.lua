-- Facts projection for state diagram pairs (doc/testing.md 3.2): a parsed
-- state Graph as plain lines, one fact per line.
--   direction LR
--   composite X "title" parent=P direction=LR states=A,B
--   state A round "label"
--     desc "description line"
--   transition A B [dotted] ["label"]
local M = {}

local function quote(s)
  return '"' .. s:gsub("\n", "\\n") .. '"'
end

local function composite(sg)
  local line = ("composite %s %s"):format(sg.id, quote(sg.title))
  line = line .. (sg.parent and (" parent=" .. sg.parent) or "")
  line = line .. (sg.direction and (" direction=" .. sg.direction) or "")
  return line .. " states=" .. table.concat(sg.nodes, ",")
end

local function transition(e)
  local line = ("transition %s %s"):format(e.from, e.to)
  line = line .. (e.style == "dotted" and " dotted" or "")
  return e.label and (line .. " " .. quote(e.label)) or line
end

---@param g table  graph from state.parse
---@return string
function M.project(g)
  local out = { "direction " .. g.direction }
  for _, sg in ipairs(g.subgraphs) do
    out[#out + 1] = composite(sg)
  end
  for _, n in ipairs(g.nodes) do
    out[#out + 1] = ("state %s %s %s"):format(n.id, n.shape, quote(n.label))
    for _, line in ipairs(n.rows and n.rows[1] or {}) do
      out[#out + 1] = "  desc " .. quote(line)
    end
  end
  for _, e in ipairs(g.edges) do
    out[#out + 1] = transition(e)
  end
  return table.concat(out, "\n")
end

return M
