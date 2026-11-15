-- Mermaid flowchart: parse to graph.model, draw with graph/draw.
-- Parses header, nodes, shapes, edges, labels and subgraphs (syntax in
-- flowchart_syntax.lua) and draws nodes and edges (subgraphs: graph/cluster.lua).
local fit = require("doc_preview.mermaid.fit")
local model = require("doc_preview.graph.model")
local source = require("doc_preview.mermaid.source")
local syntax = require("doc_preview.mermaid.flowchart_syntax")

local M = {}

-- Styling statements: accepted and ignored (nothing to draw yet).
local IGNORED = { classDef = true, class = true, style = true, linkStyle = true, click = true }

local DIRECTIONS = { TD = "TD", TB = "TD", LR = "LR", RL = "RL", BT = "BT" }

-- Split a line at `;` outside double quotes.
local function statements(line)
  local parts, cur, quoted = {}, {}, false
  for ch in line:gmatch(".") do
    if ch == '"' then
      quoted = not quoted
    end
    if ch == ";" and not quoted then
      parts[#parts + 1] = table.concat(cur)
      cur = {}
    else
      cur[#cur + 1] = ch
    end
  end
  parts[#parts + 1] = table.concat(cur)
  return parts
end

local function parse_header(stmt, lnum)
  local kind, dir = stmt:match("^(%a+)%s*(%a*)$")
  if kind ~= "flowchart" and kind ~= "graph" then
    error(("line %d: expected flowchart or graph"):format(lnum), 0)
  end
  if dir == "" then
    return "TD"
  end
  return DIRECTIONS[dir] or error(("line %d: unknown direction %s"):format(lnum, dir), 0)
end

local function skip_ws(s, pos)
  return s:find("%S", pos) or #s + 1
end

local function syntax_error(stmt, lnum)
  error(("line %d: syntax error: %s"):format(lnum, stmt), 0)
end

-- `A & B` group: declared node ids and the position after them, or nil.
local function parse_group(g, s, pos)
  local ids = {}
  while true do
    local id, np = syntax.node(g, s, pos)
    if not id then
      return nil
    end
    ids[#ids + 1] = id
    pos = skip_ws(s, np)
    if s:sub(pos, pos) ~= "&" then
      return ids, pos
    end
    pos = skip_ws(s, pos + 1)
  end
end

local function connect(g, from, to, e)
  for _, a in ipairs(from) do
    for _, b in ipairs(to) do
      model.add_edge(g, a, b, e)
    end
  end
end

local function innermost(st)
  return st.stack[#st.stack]
end

-- `subgraph id [title]`, `subgraph id`, `subgraph some title`.
local function open_subgraph(g, st, rest, lnum)
  local id, title = rest:match("^([%w_]+)%s*%[(.*)%]$")
  if id then
    title = syntax.clean(title)
  else
    id = rest:match("^[%w_]+$") or syntax.clean(rest)
  end
  if id == "" then
    error(("line %d: subgraph needs an id or title"):format(lnum), 0)
  end
  if g.sub_by_id[id] then
    error(("line %d: duplicate subgraph %s"):format(lnum, id), 0)
  end
  local parent = innermost(st)
  model.add_subgraph(g, id, title, parent and parent.id)
  st.stack[#st.stack + 1] = g.sub_by_id[id]
  st.lines[#st.stack] = lnum
end

local function close_subgraph(st, lnum)
  if #st.stack == 0 then
    error(("line %d: end without subgraph"):format(lnum), 0)
  end
  st.stack[#st.stack] = nil
end

-- Block keywords; true when the statement was one.
local function parse_block(g, st, stmt, lnum)
  local rest = stmt:match("^subgraph%s+(.+)$")
  if rest then
    open_subgraph(g, st, rest, lnum)
    return true
  end
  if stmt == "subgraph" then
    error(("line %d: subgraph needs an id or title"):format(lnum), 0)
  end
  if stmt == "end" then
    close_subgraph(st, lnum)
    return true
  end
  local dir = stmt:match("^direction%s+(%a+)$")
  if dir then
    local sg = innermost(st) or error(("line %d: direction outside subgraph"):format(lnum), 0)
    sg.direction = DIRECTIONS[dir] or error(("line %d: unknown direction %s"):format(lnum, dir), 0)
    return true
  end
  return false
end

-- A bare id that names a subgraph is an edge end, not a node.
local function drop_subgraph_nodes(g)
  local kept = {}
  for _, n in ipairs(g.nodes) do
    if g.sub_by_id[n.id] then
      g.by_id[n.id] = nil
    else
      kept[#kept + 1] = n
    end
  end
  g.nodes = kept
  for _, sg in ipairs(g.subgraphs) do
    sg.nodes = vim.tbl_filter(function(id)
      return g.by_id[id] ~= nil
    end, sg.nodes)
  end
end

-- One statement: a node group, then any number of `edge group` links.
local function parse_statement(g, stmt, lnum)
  if IGNORED[stmt:match("^(%a+)%s")] then
    return
  end
  local from, pos = parse_group(g, stmt, 1)
  while from and pos <= #stmt do
    local e, np = syntax.edge(stmt, pos)
    local to
    if e then
      to, pos = parse_group(g, stmt, skip_ws(stmt, np))
    end
    if to then
      connect(g, from, to, e)
    end
    from = to
  end
  if not from then
    syntax_error(stmt, lnum)
  end
end

-- Nodes first declared by this statement join the innermost subgraph.
local function parse_content(g, st, stmt, lnum)
  local before = #g.nodes
  parse_statement(g, stmt, lnum)
  local sg = innermost(st)
  for i = before + 1, #g.nodes do
    if sg then
      sg.nodes[#sg.nodes + 1] = g.nodes[i].id
    end
  end
end

-- Parse the source into a Graph; raises a plain string on a syntax error.
---@param lines string[]
---@return table graph
function M.parse(lines)
  local start = source.first_content(lines)
  local g
  local st = { stack = {}, lines = {} }
  for i = start, #lines do
    local line = lines[i]
    if not line:match("^%s*%%%%") then
      for _, raw in ipairs(statements(line)) do
        local stmt = raw:match("^%s*(.-)%s*$")
        if stmt ~= "" then
          if g then
            if not parse_block(g, st, stmt, i) then
              parse_content(g, st, stmt, i)
            end
          else
            g = model.new(parse_header(stmt, i))
          end
        end
      end
    end
  end
  if #st.stack > 0 then
    local sg = st.stack[#st.stack]
    error(("line %d: subgraph %s is not closed"):format(st.lines[#st.stack], sg.id), 0)
  end
  if g then
    drop_subgraph_nodes(g)
  end
  return g or model.new()
end

---@param lines string[]
---@param ctx { width: integer, charset?: string, compact?: boolean }
---@return doc_preview.Output
function M.render(lines, ctx)
  local g = M.parse(lines)
  if #g.nodes == 0 then
    error("no nodes", 0)
  end
  return fit.render(g, lines, ctx)
end

return M
