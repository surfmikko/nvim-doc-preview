-- Facts projection for class diagram pairs (doc/testing.md 3.2): a parsed
-- class Graph as plain lines, one fact per line.
--   direction LR
--   namespace N classes=A,B
--   class A "Label"
--     annotation "interface"
--     member "+int x"
--     method "+run() void"
--   note note:1 "text"
--   relation A B solid tail=triangle head=none [tail_card="1"] [head_card="*"] ["label"]
local M = {}

local function quote(s)
  return '"' .. s:gsub("\n", "\\n") .. '"'
end

local function class_facts(out, n, c)
  out[#out + 1] = ("class %s %s"):format(n.id, quote(n.label))
  if c.annotation then
    out[#out + 1] = "  annotation " .. quote(c.annotation)
  end
  for _, m in ipairs(c.members) do
    out[#out + 1] = "  member " .. quote(m)
  end
  for _, m in ipairs(c.methods) do
    out[#out + 1] = "  method " .. quote(m)
  end
end

local function relation(e)
  local line = ("relation %s %s %s tail=%s head=%s"):format(
    e.from,
    e.to,
    e.style,
    e.tail_kind,
    e.head_kind
  )
  line = line .. (e.tail_label and (" tail_card=" .. quote(e.tail_label)) or "")
  line = line .. (e.head_label and (" head_card=" .. quote(e.head_label)) or "")
  return e.label and (line .. " " .. quote(e.label)) or line
end

---@param g table  graph from class.parse
---@return string
function M.project(g)
  local out = { "direction " .. g.direction }
  for _, sg in ipairs(g.subgraphs) do
    out[#out + 1] = ("namespace %s classes=%s"):format(sg.id, table.concat(sg.nodes, ","))
  end
  for _, n in ipairs(g.nodes) do
    local c = g.classes[n.id]
    if c then
      class_facts(out, n, c)
    else
      out[#out + 1] = ("note %s %s"):format(n.id, quote(n.label))
    end
  end
  for _, e in ipairs(g.edges) do
    out[#out + 1] = relation(e)
  end
  return table.concat(out, "\n")
end

return M
