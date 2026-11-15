-- Facts projection for diagram pairs (doc/testing.md 3.2): a parsed Graph as
-- plain lines, one fact per line (sequence diagrams: project_sequence.lua), so hand-written expectations stay readable.
--   direction LR
--   node A rect "label"          (newline in a label shows as \n)
--   subgraph S "title" parent=P direction=LR nodes=A,B   (parent, direction optional)
--   edge A B solid head=arrow tail=none length=1 "label"
local M = {}

local function quote(s)
  return '"' .. s:gsub("\n", "\\n") .. '"'
end

---@param g table  graph from flowchart.parse
---@return string
function M.project(g)
  local out = { "direction " .. g.direction }
  for _, n in ipairs(g.nodes) do
    out[#out + 1] = ("node %s %s %s"):format(n.id, n.shape, quote(n.label))
  end
  for _, sg in ipairs(g.subgraphs) do
    local line = ("subgraph %s %s"):format(sg.id, quote(sg.title))
    line = line .. (sg.parent and (" parent=" .. sg.parent) or "")
    line = line .. (sg.direction and (" direction=" .. sg.direction) or "")
    out[#out + 1] = line .. " nodes=" .. table.concat(sg.nodes, ",")
  end
  for _, e in ipairs(g.edges) do
    local line = ("edge %s %s %s head=%s tail=%s length=%d"):format(
      e.from,
      e.to,
      e.style,
      e.head,
      e.tail,
      e.length
    )
    out[#out + 1] = e.label and (line .. " " .. quote(e.label)) or line
  end
  return table.concat(out, "\n")
end

-- Diagram kind pattern -> parser module and projection module.
local KINDS = {
  { "^sequenceDiagram$", "sequence", "project_sequence" },
  { "^classDiagram", "class", "project_class" },
  { "^stateDiagram", "state", "project_state" },
  { "^erDiagram$", "er", "project_er" },
  { "^pie$", "pie", "project_pie" },
  { "^gantt$", "gantt", "project_gantt" },
}

local function project_kind(parser, projection, lines)
  local ok, res = pcall(require("doc_preview.mermaid." .. parser).parse, lines)
  if not ok then
    return "error: " .. tostring(res)
  end
  return require("pairs." .. projection).project(res)
end

-- A parse failure is itself a fact: `error: <message>`.
---@param lines string[]
---@return string
function M.from_source(lines)
  local kind = require("doc_preview.mermaid").detect(lines) or ""
  for _, k in ipairs(KINDS) do
    if kind:match(k[1]) then
      return project_kind(k[2], k[3], lines)
    end
  end
  local ok, res = pcall(require("doc_preview.mermaid.flowchart").parse, lines)
  if not ok then
    return "error: " .. tostring(res)
  end
  return M.project(res)
end

function M.normalize(s)
  return (s:gsub("%s+$", ""):gsub("[ \t]+\n", "\n"))
end

return M
