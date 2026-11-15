-- Cluster geometry for graph/layout.lua (see graph/cluster.lua): pads against
-- members, pushing outsiders aside, border rows between layers, boxes.
local job = require("doc_preview.core.job")
local text = require("doc_preview.core.text")

local M = {}

local LIMIT = 50

-- Pads sit directly against the members next to them.
function M.snug(layers, items)
  for _, keys in ipairs(layers) do
    for i = #keys, 1, -1 do
      local it = items[keys[i]]
      if it.pad == "L" then
        it.x = items[keys[i + 1]].x - it.c
      end
    end
    for i = 1, #keys do
      local it = items[keys[i]]
      if it.pad == "R" then
        local prev = items[keys[i - 1]]
        it.x = prev.x + prev.c
      end
    end
  end
end

local function title_width(sg)
  return text.width(sg.title) + 6
end

-- Cross-axis rectangle [lo, hi) of a cluster.
local function bounds(cl, items, sg)
  local lo, hi = math.huge, -math.huge
  for _, it in pairs(items) do
    if it.inset and it.inset[sg.id] then
      lo, hi = math.min(lo, it.x), math.max(hi, it.x + it.c)
    end
  end
  if not cl.horizontal then
    hi = math.max(hi, lo + title_width(sg))
  end
  return lo, hi
end

local function shift(keys, items, from, to, delta)
  for i = from, to do
    items[keys[i]].x = items[keys[i]].x + delta
  end
end

-- Space an outsider keeps from the rectangle: none for the pad of an
-- enclosing cluster (it is that cluster's border).
local function outside_gap(it, sg, cl, cross)
  if it.owner and cl.chain_set[sg.id][it.owner] then
    return 0
  end
  return math.max(cross, 1)
end

-- Push the outsiders of one layer clear of the rectangle [lo, hi).
local function push(keys, items, cl, sg, lo, hi, cross)
  local first, last
  for i, key in ipairs(keys) do
    if items[key].inset[sg.id] then
      first, last = first or i, i
    end
  end
  local moved = false
  for j = first - 1, 1, -1 do
    local it = items[keys[j]]
    local over = it.x + it.c + outside_gap(it, sg, cl, cross) - lo
    if over > 0 then
      shift(keys, items, 1, j, -over)
      moved = true
    end
  end
  for j = last + 1, #keys do
    local it = items[keys[j]]
    local over = hi + outside_gap(it, sg, cl, cross) - it.x
    if over > 0 then
      shift(keys, items, j, #keys, over)
      moved = true
    end
  end
  return moved
end

-- Make room until no layer has an outsider inside a cluster's cross extent,
-- then move everything back to x >= 0.
function M.fix(cl, layers, items, cross)
  for _ = 1, LIMIT do
    job.yield_point()
    local moved = false
    for _, sg in ipairs(cl.list) do
      local lo, hi = bounds(cl, items, sg)
      for l = cl.span[sg.id].first, cl.span[sg.id].last do
        moved = push(layers[l], items, cl, sg, lo, hi, cross) or moved
      end
    end
    if not moved then
      break
    end
  end
  local low = math.huge
  for _, it in pairs(items) do
    low = math.min(low, it.x)
  end
  for _, it in pairs(items) do
    it.x = it.x - low
  end
end

-- Rows (columns when horizontal) a cluster border takes in front of its
-- first layer and behind its last: one per border (nested clusters starting
-- or ending in the same layer each need their own) plus one blank row where
-- an edge arrives or leaves. Returns per-layer maxima for the gaps.
---@return table open  layer -> rows before it
---@return table close  layer -> rows after it
function M.rows(cl)
  local function depth(sg, edge)
    local at, best = cl.span[sg.id][edge], 0
    for _, id in ipairs(sg.children) do
      local s = cl.span[id]
      if s and s[edge] == at then
        best = math.max(best, depth(cl.g.sub_by_id[id], edge))
      end
    end
    return best + 1
  end
  local open, close = {}, {}
  cl.rows = {}
  for _, sg in ipairs(cl.list) do
    local s = cl.span[sg.id]
    local o, c = depth(sg, "first") + 1, depth(sg, "last") + 1
    cl.rows[sg.id] = { open = o, close = c }
    open[s.first] = math.max(open[s.first] or 0, o)
    close[s.last] = math.max(close[s.last] or 0, c)
  end
  return open, close
end

-- Horizontal layouts need the title along the main axis: widen the last layer
-- of a cluster that is too short for it. layer -> extra thickness.
function M.grow(cl, thick, gap)
  local grow = {}
  if not cl.horizontal then
    return grow
  end
  for i = #cl.list, 1, -1 do
    local sg = cl.list[i]
    local s = cl.span[sg.id]
    local have = cl.rows[sg.id].open + cl.rows[sg.id].close + (s.last - s.first) * gap
    for l = s.first, s.last do
      have = have + thick[l] + (grow[l] or 0)
    end
    if have < title_width(sg) then
      grow[s.last] = (grow[s.last] or 0) + title_width(sg) - have
    end
  end
  return grow
end

-- Cluster rectangles as items in (cross, main) terms: id -> {x, c, y, m}.
function M.boxes(cl, items, tops, thick)
  local boxes = {}
  for _, sg in ipairs(cl.list) do
    local s, r = cl.span[sg.id], cl.rows[sg.id]
    local lo, hi = bounds(cl, items, sg)
    local top = tops[s.first] - r.open
    boxes[sg.id] =
      { x = lo, c = hi - lo, y = top, m = tops[s.last] + thick[s.last] + r.close - top }
  end
  return boxes
end

return M
