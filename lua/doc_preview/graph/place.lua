-- Cross-axis coordinates for graph/layout.lua: pack each layer, then align
-- items towards their neighbours. `gap(keyA, keyB)` is the space between two
-- neighbouring items.
local job = require("doc_preview.core.job")

local M = {}

-- Pack each layer, centred on the widest one.
function M.pack(layers, items, gap)
  local widths, widest = {}, 0
  for l, keys in ipairs(layers) do
    local w = 0
    for i, key in ipairs(keys) do
      w = w + items[key].c + (i > 1 and gap(keys[i - 1], key) or 0)
    end
    widths[l] = w
    widest = math.max(widest, widths[l])
  end
  for l, keys in ipairs(layers) do
    local x = math.floor((widest - widths[l]) / 2)
    for i, key in ipairs(keys) do
      x = x + (i > 1 and gap(keys[i - 1], key) or 0)
      items[key].x = x
      x = x + items[key].c
    end
  end
end

-- Mean centre of each item's neighbours, as the wanted position.
local function wanted(keys, neighbours, items)
  local want = {}
  for i, key in ipairs(keys) do
    local it = items[key]
    local sum, n = 0, 0
    for _, nb in ipairs(neighbours[key] or {}) do
      sum, n = sum + items[nb].x + items[nb].c / 2, n + 1
    end
    want[i] = n > 0 and math.floor(sum / n - it.c / 2 + 0.5) or it.x
  end
  return want
end

local function sweep_forward(keys, want, items, gap)
  local fwd = {}
  for i, key in ipairs(keys) do
    fwd[i] = want[i]
    if i > 1 then
      fwd[i] = math.max(want[i], fwd[i - 1] + items[keys[i - 1]].c + gap(keys[i - 1], key))
    end
  end
  return fwd
end

local function sweep_backward(keys, want, items, gap)
  local bwd = {}
  for i = #keys, 1, -1 do
    bwd[i] = want[i]
    if i < #keys then
      bwd[i] = math.min(want[i], bwd[i + 1] - gap(keys[i], keys[i + 1]) - items[keys[i]].c)
    end
  end
  return bwd
end

-- Move items towards the mean centre of their neighbours. Overlaps are resolved
-- by averaging a left-to-right and a right-to-left placement, which keeps the
-- order and the gap and spreads a group of items symmetrically.
local function align_layer(keys, neighbours, items, gap)
  local want = wanted(keys, neighbours, items)
  local fwd = sweep_forward(keys, want, items, gap)
  local bwd = sweep_backward(keys, want, items, gap)
  for i, key in ipairs(keys) do
    items[key].x = math.floor((fwd[i] + bwd[i]) / 2)
  end
end

function M.align(layers, items, adj, gap)
  for _ = 1, 2 do
    for l = 2, #layers do
      job.yield_point()
      align_layer(layers[l], adj.up, items, gap)
    end
    for l = #layers - 1, 1, -1 do
      job.yield_point()
      align_layer(layers[l], adj.down, items, gap)
    end
  end
  local lo = math.huge
  for _, it in pairs(items) do
    lo = math.min(lo, it.x)
  end
  for _, it in pairs(items) do
    it.x = it.x - lo
  end
end

return M
