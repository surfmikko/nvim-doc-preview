-- Layered (Sugiyama-style) layout, pure: Graph -> Layout (doc/diagram-model.md 1).
-- Layout { nodes = {id -> {x,y,w,h}}, dummies = {key -> {x,y,w,h}}, layers = {{key,...}},
-- edges = {i -> {reversed, loop, keys}}, width, height }.
-- Layers follow edge direction; `keys` are node ids plus dummy keys of a long edge,
-- ordered from the source layer to the target layer (back edges are reversed, so
-- `keys` then runs from edge.to to edge.from). `clusters` maps a subgraph id to
-- its box (see graph/cluster.lua); `open`/`close` give the border rows each
-- layer gap holds for cluster borders. An edge to a subgraph id attaches to
-- the subgraph's first member. Layout is done top-down on (cross, main)
-- extents and mapped to x/y per direction.
local cluster = require("doc_preview.graph.cluster")
local box = require("doc_preview.graph.cluster_box")
local place = require("doc_preview.graph.place")
local job = require("doc_preview.core.job")
local shapes = require("doc_preview.graph.shapes")

local M = {}

local SWEEPS = 4

-- cross = gap between nodes of a layer, main = gap between layers (character cells)
local SPACING = {
  TD = { cross = 4, main = 3 },
  BT = { cross = 4, main = 3 },
  LR = { cross = 1, main = 8 },
  RL = { cross = 1, main = 8 },
}
local COMPACT = {
  TD = { cross = 2, main = 1 },
  BT = { cross = 2, main = 1 },
  LR = { cross = 0, main = 4 },
  RL = { cross = 0, main = 4 },
}

-- Real edges between distinct known nodes: { index, from, to }.
local function collect_edges(g)
  local list = {}
  for i, e in ipairs(g.edges) do
    local from, to = cluster.endpoint(g, e.from), cluster.endpoint(g, e.to)
    if from and to and from ~= to then
      list[#list + 1] = { index = i, from = from, to = to, minlen = math.max(e.length or 1, 1) }
    end
  end
  return list
end

-- DFS in node and edge order; an edge to a node on the stack is reversed.
local function find_back_edges(g, edges)
  local out = {}
  for _, e in ipairs(edges) do
    out[e.from] = out[e.from] or {}
    table.insert(out[e.from], e)
  end
  local state = {}
  local function visit(id)
    state[id] = "open"
    for _, e in ipairs(out[id] or {}) do
      if state[e.to] == "open" then
        e.reversed = true
      elseif not state[e.to] then
        visit(e.to)
      end
    end
    state[id] = "done"
  end
  for _, n in ipairs(g.nodes) do
    if not state[n.id] then
      visit(n.id)
    end
  end
end

-- Set src/dst on each edge (flipped by `reversed`); out-edges and in-degrees per node.
local function orient(g, edges)
  local out, indeg = {}, {}
  for _, n in ipairs(g.nodes) do
    indeg[n.id] = 0
  end
  for _, e in ipairs(edges) do
    e.src, e.dst = e.from, e.to
    if e.reversed then
      e.src, e.dst = e.to, e.from
    end
    out[e.src] = out[e.src] or {}
    table.insert(out[e.src], e)
    indeg[e.dst] = indeg[e.dst] + 1
  end
  return out, indeg
end

-- Longest-path layering over the acyclic edge set (edges oriented by `reversed`).
local function assign_layers(g, edges)
  local out, indeg = orient(g, edges)
  local layer, queue = {}, {}
  for _, n in ipairs(g.nodes) do
    layer[n.id] = 1
    if indeg[n.id] == 0 then
      queue[#queue + 1] = n.id
    end
  end
  local head = 1
  while queue[head] do
    local id = queue[head]
    head = head + 1
    for _, e in ipairs(out[id] or {}) do
      layer[e.dst] = math.max(layer[e.dst], layer[id] + e.minlen)
      indeg[e.dst] = indeg[e.dst] - 1
      if indeg[e.dst] == 0 then
        queue[#queue + 1] = e.dst
      end
    end
  end
  return layer
end

-- Items: key -> { key, layer, c, m (cross and main extent), id? }; layers hold keys.
local function build_layers(g, layer, horizontal)
  local items, layers = {}, {}
  local function add(key, l, c, m, id)
    items[key] = { key = key, layer = l, c = c, m = m, id = id }
    table.insert(layers[l], key)
  end
  local top = 0
  for _, n in ipairs(g.nodes) do
    top = math.max(top, layer[n.id])
  end
  for l = 1, top do
    layers[l] = {}
  end
  for _, n in ipairs(g.nodes) do
    local w, h = shapes.size(n, horizontal)
    if horizontal then
      add(n.id, layer[n.id], h, w, n.id)
    else
      add(n.id, layer[n.id], w, h, n.id)
    end
  end
  return items, layers
end

local function add_dummies(edges, layer, items, layers)
  local adj = { up = {}, down = {} }
  local function link(a, b)
    adj.down[a] = adj.down[a] or {}
    adj.up[b] = adj.up[b] or {}
    table.insert(adj.down[a], b)
    table.insert(adj.up[b], a)
  end
  for _, e in ipairs(edges) do
    local keys, prev = { e.src }, e.src
    for l = layer[e.src] + 1, layer[e.dst] - 1 do
      local key = ("\0%d:%d"):format(e.index, l)
      items[key] = { key = key, layer = l, c = 1, m = 1 }
      table.insert(layers[l], key)
      keys[#keys + 1] = key
      link(prev, key)
      prev = key
    end
    keys[#keys + 1] = e.dst
    link(prev, e.dst)
    e.keys = keys
  end
  return adj
end

local function positions(layer_keys)
  local pos = {}
  for i, key in ipairs(layer_keys) do
    pos[key] = i
  end
  return pos
end

-- Reorder one layer by the mean position of neighbours in `neighbours`;
-- items without any keep their slot. Stable.
local function reorder(layer_keys, neighbours, other_pos)
  local pos = positions(layer_keys)
  local bary = {}
  for key, i in pairs(pos) do
    local sum, n = 0, 0
    for _, nb in ipairs(neighbours[key] or {}) do
      sum, n = sum + other_pos[nb], n + 1
    end
    bary[key] = n > 0 and sum / n or i
  end
  table.sort(layer_keys, function(a, b)
    if bary[a] ~= bary[b] then
      return bary[a] < bary[b]
    end
    return pos[a] < pos[b]
  end)
end

-- `group` (optional) restores cluster contiguity after each reordering.
local function order_layers(layers, adj, group)
  for _ = 1, SWEEPS do
    for l = 2, #layers do
      job.yield_point()
      reorder(layers[l], adj.up, positions(layers[l - 1]))
      if group then
        group(layers[l])
      end
    end
    for l = #layers - 1, 1, -1 do
      job.yield_point()
      reorder(layers[l], adj.down, positions(layers[l + 1]))
      if group then
        group(layers[l])
      end
    end
  end
end

local function thickness(layers, items)
  local thick = {}
  for l, keys in ipairs(layers) do
    local t = 0
    for _, key in ipairs(keys) do
      t = math.max(t, items[key].m)
    end
    thick[l] = t
  end
  return thick
end

-- Main-axis offsets: layers stacked with `gap` plus the cluster border rows
-- (`ex.open`, `ex.close`), each as thick as its tallest item (plus `ex.grow`).
local function stack(layers, items, gap, ex)
  local y, tops = ex.open[1] or 0, {}
  for l, keys in ipairs(layers) do
    local t = ex.thick[l]
    tops[l] = y
    for _, key in ipairs(keys) do
      items[key].y = y + math.floor((t - items[key].m) / 2)
    end
    y = y + t + gap + (ex.close[l] or 0) + (ex.open[l + 1] or 0)
  end
  return math.max(y - gap, 0), tops
end

local function to_box(it, dir, total_main)
  local cross, main = it.x, it.y
  if dir == "BT" or dir == "RL" then
    main = total_main - main - it.m
  end
  if dir == "LR" or dir == "RL" then
    return { x = main, y = cross, w = it.m, h = it.c }
  end
  return { x = cross, y = main, w = it.c, h = it.m }
end

local function new_layout(layers, items, ex)
  local lay =
    { nodes = {}, dummies = {}, layers = {}, edges = {}, clusters = {}, width = 0, height = 0 }
  lay.open, lay.close = ex.open, ex.close
  for l, keys in ipairs(layers) do
    lay.layers[l] = vim.tbl_filter(function(key)
      return not items[key].pad
    end, keys)
  end
  return lay
end

local function extend(lay, b)
  lay.width = math.max(lay.width, b.x + b.w)
  lay.height = math.max(lay.height, b.y + b.h)
end

local function add_boxes(lay, g, items, total_main, ex)
  for key, it in pairs(items) do
    if not it.pad then
      local b = to_box(it, g.direction, total_main)
      lay[it.id and "nodes" or "dummies"][key] = b
      extend(lay, b)
    end
  end
  for id, it in pairs(ex.boxes) do
    lay.clusters[id] = to_box(it, g.direction, total_main)
    extend(lay, lay.clusters[id])
  end
  for _, sg in ipairs(cluster.empties(g)) do
    lay.clusters[sg.id] = lay.nodes[sg.id]
  end
end

local function add_loops(lay, g)
  for i, e in ipairs(g.edges) do
    if g.by_id[e.from] and g.by_id[e.to] and e.from == e.to then
      lay.edges[i] = { loop = true, keys = { e.from } }
    end
  end
end

local function finish(g, edges, layers, items, total_main, ex)
  local lay = new_layout(layers, items, ex)
  add_boxes(lay, g, items, total_main, ex)
  add_loops(lay, g)
  for _, e in ipairs(edges) do
    lay.edges[e.index] = { reversed = e.reversed or false, keys = e.keys }
  end
  return lay
end

-- Empty subgraphs become leaf nodes titled like the subgraph.
local function with_empties(g)
  local empties = cluster.empties(g)
  if #empties == 0 then
    return g
  end
  local lg = vim.tbl_extend(
    "force",
    g,
    { nodes = vim.list_slice(g.nodes), by_id = vim.tbl_extend("force", {}, g.by_id) }
  )
  for _, sg in ipairs(empties) do
    local n = { id = sg.id, label = (" %s "):format(sg.title), shape = "rect" }
    lg.nodes[#lg.nodes + 1] = n
    lg.by_id[sg.id] = n
  end
  return lg
end

local function spacing(g, opts)
  local sp = ((opts and opts.compact) and COMPACT or SPACING)[g.direction]
  if g.end_room then
    sp = { cross = sp.cross, main = math.max(sp.main, 2 * g.end_room + 1) }
  end
  return sp
end

-- Order each layer; clusters (if any) are made contiguous, then kept in one order across layers.
local function order_with_clusters(layers, adj, items, cl)
  order_layers(layers, adj, cl and function(keys)
    cluster.group(keys, items)
  end)
  if cl then
    local rank = cluster.rank(cl, layers, items)
    for _, keys in ipairs(layers) do
      cluster.group(keys, items, rank)
    end
  end
end

-- Cluster border rows and layer thickness (`ex`) once the cross axis is placed.
local function extents(cl, layers, items, sp)
  local ex = { open = {}, close = {}, boxes = {} }
  if cl then
    box.snug(layers, items)
    box.fix(cl, layers, items, sp.cross)
    ex.open, ex.close = box.rows(cl)
  end
  ex.thick = thickness(layers, items)
  if cl then
    for l, extra in pairs(box.grow(cl, ex.thick, sp.main)) do
      ex.thick[l] = ex.thick[l] + extra
    end
  end
  return ex
end

---@param g table  validated graph
---@param opts? { compact?: boolean }
---@return table layout
function M.layout(g, opts)
  g = with_empties(g)
  local dir = g.direction
  local horizontal = dir == "LR" or dir == "RL"
  local sp = spacing(g, opts)
  local edges = collect_edges(g)
  find_back_edges(g, edges)
  local layer = assign_layers(g, edges)
  local items, layers = build_layers(g, layer, horizontal)
  local adj = add_dummies(edges, layer, items, layers)
  local cl = cluster.setup(g, items, layers, edges, horizontal)
  local function gap(a, b)
    return cluster.gap(items[a], items[b], sp.cross)
  end
  order_with_clusters(layers, adj, items, cl)
  place.pack(layers, items, gap)
  place.align(layers, items, adj, gap)
  local ex = extents(cl, layers, items, sp)
  local total, tops = stack(layers, items, sp.main, ex)
  if cl then
    ex.boxes = box.boxes(cl, items, tops, ex.thick)
  end
  return finish(g, edges, layers, items, total, ex)
end

return M
