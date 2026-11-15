-- Subgraph clusters for graph/layout.lua (doc/diagram-model.md 1), pure.
-- A cluster is a rectangle around its members. To keep non-members out of it
-- the layout adds, per layer of the cluster's span, a left and a right "pad"
-- item next to the members; members stay contiguous in each layer, sibling
-- clusters keep one order across layers, and `fix` pushes outsiders aside
-- where another layer made the rectangle wider. An empty subgraph is laid out
-- as a leaf box; an edge to a subgraph id ends at its first member (documented
-- in doc/diagram-model.md). Subgraph `direction` is ignored.

local M = {}

local function is_empty(sg)
  return #sg.nodes == 0 and #sg.children == 0
end

---@return table[] subgraphs without nodes and children
function M.empties(g)
  return vim.tbl_filter(is_empty, g.subgraphs)
end

-- First node of a subgraph (or its first empty descendant): where edges to
-- the subgraph id attach.
local function representative(g, sg)
  if sg.nodes[1] then
    return sg.nodes[1]
  end
  if is_empty(sg) then
    return sg.id
  end
  for _, id in ipairs(sg.children) do
    local r = representative(g, g.sub_by_id[id])
    if r then
      return r
    end
  end
end

---@return string? node id an edge end resolves to
function M.endpoint(g, id)
  if g.by_id[id] then
    return id
  end
  local sg = (g.sub_by_id or {})[id]
  return sg and representative(g, sg) or nil
end

-- Subgraph id -> its ancestor chain including itself, outermost first.
local function chain_of(g, sid)
  local list = {}
  while sid do
    table.insert(list, 1, sid)
    sid = g.sub_by_id[sid].parent
  end
  return list
end

local function set_of(list)
  local set = {}
  for _, v in ipairs(list) do
    set[v] = true
  end
  return set
end

local function owners(g)
  local owner = {}
  for _, sg in ipairs(g.subgraphs) do
    for _, id in ipairs(sg.nodes) do
      owner[id] = sg.id
    end
    if is_empty(sg) then
      owner[sg.id] = sg.parent
    end
  end
  return owner
end

local function set_chain(it, chain)
  it.chain, it.inset = chain, set_of(chain)
end

local function common_prefix(a, b)
  local out = {}
  for i = 1, math.min(#a, #b) do
    if a[i] ~= b[i] then
      break
    end
    out[i] = a[i]
  end
  return out
end

-- Spans of the clusters that hold at least one real item: id -> {first, last}.
local function spans(items)
  local span = {}
  for _, it in pairs(items) do
    for _, cid in ipairs(it.id and it.chain or {}) do
      local s = span[cid] or { first = it.layer, last = it.layer }
      s.first, s.last = math.min(s.first, it.layer), math.max(s.last, it.layer)
      span[cid] = s
    end
  end
  return span
end

local function add_pads(g, cl, items, layers, horizontal)
  for _, sg in ipairs(cl.list) do
    local chain = chain_of(g, sg.id)
    for l = cl.span[sg.id].first, cl.span[sg.id].last do
      for _, side in ipairs({ "L", "R" }) do
        local key = ("\1%s:%s:%d"):format(side, sg.id, l)
        local it =
          { key = key, layer = l, c = horizontal and 1 or 2, m = 1, owner = sg.id, pad = side }
        set_chain(it, chain)
        items[key] = it
        table.insert(layers[l], key)
      end
    end
  end
end

-- Membership, spans and pads; nil when the graph has no clusters.
---@param edges table[] layout edges with `keys`, `src`, `dst`
---@return table? cl
function M.setup(g, items, layers, edges, horizontal)
  if #g.subgraphs == 0 then
    return nil
  end
  local owner = owners(g)
  local chains = {}
  for _, it in pairs(items) do
    if it.id then
      chains[it.id] = chain_of(g, owner[it.id])
      set_chain(it, chains[it.id])
    end
  end
  for _, e in ipairs(edges) do
    local shared = common_prefix(chains[e.src], chains[e.dst])
    for i = 2, #e.keys - 1 do
      set_chain(items[e.keys[i]], shared)
    end
  end
  local cl = { span = spans(items), list = {}, horizontal = horizontal, g = g, chain_set = {} }
  for _, sg in ipairs(g.subgraphs) do
    if cl.span[sg.id] then
      cl.chain_set[sg.id] = set_of(chain_of(g, sg.id))
      cl.list[#cl.list + 1] = sg
    end
  end
  add_pads(g, cl, items, layers, horizontal)
  return cl
end

local function unit_for(units, order, cid, key)
  local u = units[cid or key]
  if not u then
    u = { cluster = cid, keys = {}, sum = 0, cnt = 0, first = #order }
    units[cid or key] = u
    order[#order + 1] = u
  end
  return u
end

-- Split `keys` into units (clusters at `depth` and loose items) in first-seen
-- order, plus the owner's own pads (`inner`, by side).
local function split_units(keys, items, depth, owner, pos, n)
  local units, order, inner = {}, {}, {}
  for _, key in ipairs(keys) do
    local it = items[key]
    if it.pad and it.owner == owner then
      inner[it.pad] = key
    else
      local u = unit_for(units, order, it.chain[depth], key)
      table.insert(u.keys, key)
      if not it.pad then
        u.sum, u.cnt = u.sum + (pos[key] - 0.5) / n, u.cnt + 1
      end
    end
  end
  return order, inner
end

local function set_values(order, rank)
  for _, u in ipairs(order) do
    u.value = u.cnt > 0 and u.sum / u.cnt or 0.5
    if u.cluster and rank and rank[u.cluster] then
      u.value = rank[u.cluster]
    end
  end
end

local function by_value(a, b)
  if a.value ~= b.value then
    return a.value < b.value
  end
  return a.first < b.first
end

-- Order one layer: units (clusters and loose items) sorted by `value`, a
-- cluster's pads first and last, recursively. `rank` (id -> number) makes
-- sibling clusters keep one order across layers.
local function arrange(keys, items, depth, owner, rank, pos, n, out)
  local order, inner = split_units(keys, items, depth, owner, pos, n)
  set_values(order, rank)
  table.sort(order, by_value)
  out[#out + 1] = inner.L
  for _, u in ipairs(order) do
    if u.cluster then
      arrange(u.keys, items, depth + 1, u.cluster, rank, pos, n, out)
    else
      out[#out + 1] = u.keys[1]
    end
  end
  out[#out + 1] = inner.R
end

-- Make every cluster contiguous in `keys` (in place).
function M.group(keys, items, rank)
  local pos = {}
  for i, key in ipairs(keys) do
    pos[key] = i
  end
  local out = {}
  arrange(keys, items, 1, nil, rank, pos, #keys, out)
  for i = 1, #keys do
    keys[i] = out[i]
  end
end

-- Mean normalised position of each cluster's real members over all layers.
function M.rank(_, layers, items)
  local sum, cnt = {}, {}
  for _, keys in ipairs(layers) do
    for i, key in ipairs(keys) do
      local it = items[key]
      for _, cid in ipairs(it.pad and {} or it.chain) do
        sum[cid] = (sum[cid] or 0) + (i - 0.5) / #keys
        cnt[cid] = (cnt[cid] or 0) + 1
      end
    end
  end
  local rank = {}
  for cid, s in pairs(sum) do
    rank[cid] = s / cnt[cid]
  end
  return rank
end

---@return number gap between neighbouring items `a` and `b`
function M.gap(a, b, cross)
  local function inside(pad, other)
    return pad.owner and other.inset[pad.owner]
  end
  if inside(a, b) or inside(b, a) then
    return 0
  end
  if a.owner or b.owner then
    return math.max(cross, 1)
  end
  return cross
end

return M
