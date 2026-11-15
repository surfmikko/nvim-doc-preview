-- Graph model shared by the diagram languages (doc/architecture.md 3):
-- { direction, nodes, edges, subgraphs }, node { id, label, shape }.
-- edge { from, to, style, head, tail, length, label? }: from/to are node ids,
-- style solid|dotted|thick, head/tail none|arrow|circle|cross, length is the
-- rank length (1 = `-->`); from/to may also be a subgraph id.
-- subgraph { id, title, parent?, direction?, nodes = {ids}, children = {ids} }:
-- a node belongs to the innermost subgraph it was first declared in.
-- Optional record fields (class, state, ER): node.rows = list of sections,
-- each a list of text lines, drawn under the title (label) of a "record"
-- shape; edge head_kind/tail_kind (none|arrow|circle|cross|open|triangle|
-- diamond|diamond_filled, overriding head/tail) and head_label/tail_label
-- (text, e.g. a cardinality, drawn beside that end).
local M = {}

local DIRECTIONS = { TD = true, LR = true, RL = true, BT = true }

---@param direction? "TD"|"LR"|"RL"|"BT"
function M.new(direction)
  return {
    direction = direction or "TD",
    nodes = {},
    edges = {},
    subgraphs = {},
    by_id = {},
    sub_by_id = {},
  }
end

-- Add a node, or on redeclaration replace its label and shape when given
-- (as mermaid.js does; an omitted shape keeps the earlier one).
---@param label? string  defaults to the id
---@param shape? string  defaults to "rect"
---@param rows? string[][]  record sections
function M.add_node(g, id, label, shape, rows)
  local n = g.by_id[id]
  if n then
    n.label = label or n.label
    n.shape = shape or n.shape
    n.rows = rows or n.rows
    return n
  end
  n = { id = id, label = label or id, shape = shape or "rect", rows = rows }
  g.nodes[#g.nodes + 1] = n
  g.by_id[id] = n
  return n
end

---@param parent? string  id of the enclosing subgraph
function M.add_subgraph(g, id, title, parent)
  local sg = { id = id, title = title or id, parent = parent, nodes = {}, children = {} }
  g.subgraphs[#g.subgraphs + 1] = sg
  g.sub_by_id[id] = sg
  if parent then
    local kids = g.sub_by_id[parent].children
    kids[#kids + 1] = id
  end
  return sg
end

local STYLES = { solid = true, dotted = true, thick = true }
local ENDS = { none = true, arrow = true, circle = true, cross = true }
-- ER cardinality kinds (one, zero_one, zero_many, one_many) are drawn as two
-- cells (graph/ends.lua); a graph with them sets `end_room = 2` so the
-- layout leaves a gap holding both ends.
local KINDS = vim.tbl_extend("error", ENDS, {
  open = true,
  triangle = true,
  diamond = true,
  diamond_filled = true,
  one = true,
  zero_one = true,
  zero_many = true,
  one_many = true,
})

---@param opts? { style?: string, head?: string, tail?: string, length?: integer, label?: string, head_kind?: string, tail_kind?: string, head_label?: string, tail_label?: string }
function M.add_edge(g, from, to, opts)
  opts = opts or {}
  local e = {
    from = from,
    to = to,
    style = opts.style or "solid",
    head = opts.head or "arrow",
    tail = opts.tail or "none",
    length = opts.length or 1,
    label = opts.label,
    head_kind = opts.head_kind,
    tail_kind = opts.tail_kind,
    head_label = opts.head_label,
    tail_label = opts.tail_label,
  }
  g.edges[#g.edges + 1] = e
  return e
end

local function check_edge_basics(e, ends)
  if type(e) ~= "table" or not ends[e.from] or not ends[e.to] then
    return "edge needs existing from and to nodes or subgraphs"
  end
  if not STYLES[e.style] or not ENDS[e.head] or not ENDS[e.tail] then
    return "bad edge style, head or tail"
  end
end

local function check_edge_length(e)
  if type(e.length) ~= "number" or (e.label ~= nil and type(e.label) ~= "string") then
    return "bad edge length or label"
  end
end

local function check_edge_kinds(e)
  for _, k in ipairs({ "head_kind", "tail_kind" }) do
    if e[k] ~= nil and not KINDS[e[k]] then
      return "bad edge " .. k
    end
  end
end

local function check_edge_labels(e)
  for _, k in ipairs({ "head_label", "tail_label" }) do
    if e[k] ~= nil and type(e[k]) ~= "string" then
      return "bad edge " .. k
    end
  end
end

local function check_edge(e, ends)
  return check_edge_basics(e, ends)
    or check_edge_length(e)
    or check_edge_kinds(e)
    or check_edge_labels(e)
end

local function check_rows(rows)
  if type(rows) ~= "table" then
    return false
  end
  for _, section in ipairs(rows) do
    if type(section) ~= "table" then
      return false
    end
    for _, line in ipairs(section) do
      if type(line) ~= "string" then
        return false
      end
    end
  end
  return true
end

local function check_node(n, seen)
  if type(n) ~= "table" or type(n.id) ~= "string" or n.id == "" then
    return "node without id"
  end
  if seen[n.id] then
    return "duplicate node " .. n.id
  end
  if type(n.label) ~= "string" or type(n.shape) ~= "string" then
    return "node " .. n.id .. " needs string label and shape"
  end
  if n.rows ~= nil and not check_rows(n.rows) then
    return "node " .. n.id .. " rows must be a list of lists of strings"
  end
end

local function check_subgraph(sg, nodes, subs)
  if type(sg) ~= "table" or type(sg.id) ~= "string" or type(sg.title) ~= "string" then
    return "subgraph needs string id and title"
  end
  if sg.parent ~= nil and not subs[sg.parent] then
    return "subgraph " .. sg.id .. " has unknown parent"
  end
  for _, id in ipairs(sg.nodes) do
    if not nodes[id] then
      return "subgraph " .. sg.id .. " has unknown node " .. tostring(id)
    end
  end
  for _, id in ipairs(sg.children) do
    if not subs[id] then
      return "subgraph " .. sg.id .. " has unknown child " .. tostring(id)
    end
  end
end

local function check_header(g)
  if type(g) ~= "table" then
    return "graph must be a table"
  end
  if not DIRECTIONS[g.direction] then
    return "bad direction " .. tostring(g.direction)
  end
  if type(g.nodes) ~= "table" or type(g.edges) ~= "table" or type(g.subgraphs) ~= "table" then
    return "nodes, edges and subgraphs must be tables"
  end
end

---@return string? err
---@return table? seen  node ids
local function check_nodes(g)
  local seen = {}
  for _, n in ipairs(g.nodes) do
    local err = check_node(n, seen)
    if err then
      return err
    end
    seen[n.id] = true
  end
  return nil, seen
end

---@return string? err
---@return table? ends  ids of nodes and subgraphs
local function check_subgraphs(g, seen)
  local ends = {}
  for _, sg in ipairs(g.subgraphs) do
    local err = check_subgraph(sg, seen, g.sub_by_id)
    if err then
      return err
    end
    ends[sg.id] = true
  end
  for id in pairs(seen) do
    ends[id] = true
  end
  return nil, ends
end

local function check_edges(g, ends)
  for _, e in ipairs(g.edges) do
    local err = check_edge(e, ends)
    if err then
      return err
    end
  end
end

---@return boolean ok
---@return string|nil err
function M.validate(g)
  local err = check_header(g)
  if err then
    return false, err
  end
  local seen, ends
  err, seen = check_nodes(g)
  if err then
    return false, err
  end
  err, ends = check_subgraphs(g, seen)
  if err then
    return false, err
  end
  err = check_edges(g, ends)
  if err then
    return false, err
  end
  return true
end

return M
