-- Orthogonal edge routing on the layout's channels, pure geometry
-- (doc/diagram-model.md 1). For each edge with a layout entry:
-- { index, loop, reversed, polys = {{ {x,y}, ... }, ...}, first, last,
--   forward, pairs }. `polys` has one polyline per layer step (a long edge
-- passes through its dummy cells); `first` and `last` are the cells next to
-- the source-layer and target-layer node borders. A loop leaves right of the
-- bottom corner and returns into the right border; it needs two columns right
-- of the layout (see M.margin).
local job = require("doc_preview.core.job")

local M = {}

local FORWARD = { TD = "down", BT = "up", LR = "right", RL = "left" }
local BACKWARD = { down = "up", up = "down", right = "left", left = "right" }

M.FORWARD, M.BACKWARD = FORWARD, BACKWARD

local function centre(b)
  return b.x + math.floor(b.w / 2), b.y + math.floor(b.h / 2)
end

-- Cell just outside the border where an edge leaves (`leaving`) or enters a
-- node; a dummy is a single cell that lines pass through.
local function port(b, dir, leaving, dummy)
  if dummy then
    return { x = b.x, y = b.y }
  end
  local cx, cy = centre(b)
  if dir == "TD" or dir == "BT" then
    local down = (dir == "TD") == leaving
    return { x = cx, y = down and b.y + b.h or b.y - 1 }
  end
  local right = (dir == "LR") == leaving
  return { x = right and b.x + b.w or b.x - 1, y = cy }
end

local function dedupe(pts)
  local list = {}
  for _, p in ipairs(pts) do
    local last = list[#list]
    if not last or last.x ~= p.x or last.y ~= p.y then
      list[#list + 1] = p
    end
  end
  return list
end

-- Main-axis extent [lo, hi) of every layer, from its boxes.
local function layer_extents(lay, horiz)
  local ext = {}
  for l, keys in ipairs(lay.layers) do
    local lo, hi = math.huge, -math.huge
    for _, key in ipairs(keys) do
      local b = lay.nodes[key] or lay.dummies[key]
      local from, size = b.y, b.h
      if horiz then
        from, size = b.x, b.w
      end
      lo, hi = math.min(lo, from), math.max(hi, from + size)
    end
    ext[l] = { lo = lo, hi = hi }
  end
  return ext
end

-- Polyline from p to q: along the main axis to a jog line in the middle of the
-- gap between the two layers (`gap` = first and last main coordinate of it),
-- across, on. Jogging only in the gap keeps lines clear of sibling nodes.
local function connect(p, q, dir, gap)
  local horiz = dir == "LR" or dir == "RL"
  local function at(m, c)
    return horiz and { x = m, y = c } or { x = c, y = m }
  end
  local pc, qc = p.x, q.x
  if horiz then
    pc, qc = p.y, q.y
  end
  local jm = gap[1] + math.floor((gap[2] - gap[1]) / 2)
  return { poly = dedupe({ p, at(jm, pc), at(jm, qc), q }), jog = jm, horiz = horiz }
end

local function lookup(lay, key)
  if lay.nodes[key] then
    return lay.nodes[key], false
  end
  return lay.dummies[key], true
end

-- Free gap between layer `la` and the next one, whichever way the flow runs,
-- without the rows that cluster borders take at either end.
local function gap_between(ext, la, dir, lay)
  local a, b = ext[la], ext[la + 1]
  local close, open = (lay.close or {})[la] or 0, (lay.open or {})[la + 1] or 0
  if dir == "TD" or dir == "LR" then
    return { a.hi + close, b.lo - 1 - open }
  end
  return { b.hi + open, a.lo - 1 - close }
end

-- One-row gap (both ports on the same main coordinate): a jog would put a
-- stray line beside the arrowhead, so move a port along its border to a
-- column both nodes share, if there is one.
local function align_ports(p, q, a, b, dir)
  if dir ~= "TD" and dir ~= "BT" or p.y ~= q.y or p.x == q.x then
    return
  end
  if p.x > b.x and p.x < b.x + b.w - 1 then
    q.x = p.x
  elseif q.x > a.x and q.x < a.x + a.w - 1 then
    p.x = q.x
  end
end

local function route_chain(info, lay, dir, ext, layer_of)
  local r = { reversed = info.reversed, polys = {}, pairs = {}, forward = FORWARD[dir] }
  for i = 1, #info.keys - 1 do
    local a, adummy = lookup(lay, info.keys[i])
    local b, bdummy = lookup(lay, info.keys[i + 1])
    local gap = gap_between(ext, layer_of[info.keys[i]], dir, lay)
    local p, q = port(a, dir, true, adummy), port(b, dir, false, bdummy)
    if not adummy and not bdummy then
      align_ports(p, q, a, b, dir)
    end
    local pair = connect(p, q, dir, gap)
    r.polys[i] = pair.poly
    r.pairs[i] = pair
  end
  r.first = r.polys[1][1]
  local last = r.polys[#r.polys]
  r.last = last[#last]
  return r
end

local function route_loop(info, lay)
  local b = lay.nodes[info.keys[1]]
  local _, cy = centre(b)
  local right = b.x + b.w + 1
  local bottom = b.y + b.h - 1
  local poly = {
    { x = right - 1, y = bottom },
    { x = right, y = bottom },
    { x = right, y = cy },
    { x = right - 1, y = cy },
  }
  return {
    loop = true,
    polys = { poly },
    pairs = {},
    first = poly[1],
    last = poly[4],
    forward = "left",
    back = "left",
    label_at = { x = right + 2, y = cy },
  }
end

---@param g table  graph
---@param lay table  graph.layout result
---@return table[] routes  indexed like g.edges (nil for edges without layout)
function M.route(g, lay)
  local routes = {}
  local horiz = g.direction == "LR" or g.direction == "RL"
  local ext, layer_of = layer_extents(lay, horiz), {}
  for l, keys in ipairs(lay.layers) do
    for _, key in ipairs(keys) do
      layer_of[key] = l
    end
  end
  for i in ipairs(g.edges) do
    local info = lay.edges[i]
    if info then
      job.yield_point()
      routes[i] = info.loop and route_loop(info, lay)
        or route_chain(info, lay, g.direction, ext, layer_of)
      routes[i].index = i
    end
  end
  return routes
end

local function by_middle(list)
  local mid = (#list + 1) / 2
  local order = {}
  for i = 1, #list do
    order[i] = i
  end
  table.sort(order, function(a, b)
    local da, db = math.abs(a - mid), math.abs(b - mid)
    if da ~= db then
      return da < db
    end
    return a < b
  end)
  return vim.tbl_map(function(i)
    return list[i]
  end, order)
end

-- Cells of the vertical runs of a polyline.
local function vertical_cells(poly)
  local cells = {}
  for i = 1, #poly - 1 do
    local a, b = poly[i], poly[i + 1]
    if a.x == b.x then
      for y = math.min(a.y, b.y), math.max(a.y, b.y) do
        cells[#cells + 1] = { x = a.x, y = y }
      end
    end
  end
  return cells
end

local function vertical_spots(r, lw, spots)
  local poly, pair = r.polys[1], r.pairs[1]
  local p, q = poly[1], poly[#poly]
  if p.x ~= q.x then
    local run = math.abs(p.x - q.x) - 1
    if run >= lw + 2 then
      spots[#spots + 1] = {
        x = math.min(p.x, q.x) + 1 + math.floor((run - lw - 2) / 2),
        y = pair.jog,
        on_line = true,
      }
    end
  end
  local cells = #poly == 1 and { p } or vertical_cells(poly)
  for _, c in ipairs(by_middle(cells)) do
    spots[#spots + 1] = { x = c.x + 2, y = c.y }
  end
end

local function horizontal_spots(r, lw, spots)
  local poly = r.polys[1]
  for i = 1, math.max(#poly - 1, 1) do
    local a, b = poly[i], poly[i + 1] or poly[i]
    if a.y == b.y then
      local run = math.abs(a.x - b.x) - 1
      local x = math.min(a.x, b.x) + 1 + math.max(math.floor((run - lw) / 2), 0)
      spots[#spots + 1] = { x = x, y = a.y - 1 }
      spots[#spots + 1] = { x = x, y = a.y + 1 }
    end
  end
end

-- Candidate positions for a label of display width `lw`, best first. A spot
-- with `on_line` is a padded text laid over the edge itself (width lw + 2).
---@return table[]
function M.label_spots(r, lw, dir)
  local spots = {}
  if r.loop then
    spots[1] = r.label_at
  elseif dir == "LR" or dir == "RL" then
    horizontal_spots(r, lw, spots)
  else
    vertical_spots(r, lw, spots)
  end
  spots[#spots + 1] = { x = r.first.x + 2, y = r.first.y }
  return spots
end

-- Extra columns right and rows below the layout that loops need.
---@return integer cols
---@return integer rows
function M.margin(routes)
  for _, r in pairs(routes) do
    if r.loop then
      return 2, 0
    end
  end
  return 0, 0
end

return M
