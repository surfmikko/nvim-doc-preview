-- Graph + layout -> canvas -> Output (doc/diagram-model.md 1): subgraph boxes,
-- node shapes, routed edges with styles and end markers, edge labels. Never wider than
-- ctx.width (the canvas clips and reports the natural width; width
-- fallbacks live in mermaid/flowchart).
local canvas = require("doc_preview.core.canvas")
local ends = require("doc_preview.graph.ends")
local job = require("doc_preview.core.job")
local route = require("doc_preview.graph.route")
local shapes = require("doc_preview.graph.shapes")
local text = require("doc_preview.core.text")

local M = {}

local BORDER, LABEL = "DocPreviewDiagramBorder", "DocPreviewDiagramLabel"
local EDGE = "DocPreviewDiagramEdge"

-- Longest prefix of `s` that fits in `max` columns; "..." marks a cut.
local function fit(s, max)
  if text.width(s) <= max then
    return s
  end
  local dots = math.min(max, 3)
  local keep = max - dots
  local cut = ""
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if text.width(cut .. ch) > keep then
      break
    end
    cut = cut .. ch
  end
  return cut .. ("."):rep(dots)
end

-- Copy of `g` whose node labels fit into `width` columns, line by line.
---@param g table  validated graph
---@param width integer
---@return table
function M.fit(g, width)
  local copy = vim.tbl_extend("force", g, { nodes = {}, by_id = {} })
  for i, n in ipairs(g.nodes) do
    local max = math.max(width - 2 * shapes.get(n.shape).pad - 2, 0)
    local lines = {}
    for line in (n.label .. "\n"):gmatch("(.-)\n") do
      lines[#lines + 1] = fit(line, max)
    end
    local rows = n.rows
      and vim.tbl_map(function(section)
        return vim.tbl_map(function(line)
          return fit(line, max)
        end, section)
      end, n.rows)
    copy.nodes[i] = vim.tbl_extend("force", n, { label = table.concat(lines, "\n"), rows = rows })
    copy.by_id[n.id] = copy.nodes[i]
  end
  return copy
end

-- Title centred, rows left-aligned; dividers between the sections.
local function draw_node(c, n, b)
  shapes.draw(n.shape, c, b.x, b.y, b.w, b.h, BORDER)
  local pad = shapes.get(n.shape).pad
  if shapes.get(n.shape).bare then
    return
  end
  local inner = b.w - 2 - 2 * pad
  local j, dividers = 0, {}
  for i, section in ipairs(shapes.sections(n)) do
    if i > 1 then
      dividers[#dividers + 1] = 1 + j
      j = j + 1
    end
    for _, line in ipairs(section) do
      local slack = inner - text.width(line)
      local x = b.x + 1 + pad + (i == 1 and math.max(math.floor(slack / 2), 0) or 0)
      c:put(x, b.y + 1 + j, line, LABEL)
      j = j + 1
    end
  end
  shapes.divide(c, b.x, b.y, b.w, dividers, BORDER)
end

-- Subgraph box; the title is drawn later (draw_titles), over the edges.
local function draw_cluster(c, b)
  shapes.draw("rect", c, b.x, b.y, b.w, b.h, BORDER)
end

-- Does a vertical edge run cross row `y` within columns [x0, x1]?
local function crosses(routes, y, x0, x1)
  for _, r in pairs(routes) do
    for _, poly in ipairs(r.polys) do
      for i = 1, #poly - 1 do
        local p, q = poly[i], poly[i + 1]
        if
          p.x == q.x
          and p.x >= x0
          and p.x <= x1
          and math.min(p.y, q.y) <= y
          and y <= math.max(p.y, q.y)
        then
          return true
        end
      end
    end
  end
  return false
end

-- Title in the top border: left, or right when an edge enters there.
local function draw_title(c, routes, sg, b)
  if b.w < 7 then
    return
  end
  local title = (" %s "):format(fit((sg.title:gsub("\n", " ")), b.w - 6))
  local w = text.width(title)
  local x = b.x + 2
  if
    crosses(routes, b.y, x, x + w - 1)
    and not crosses(routes, b.y, b.x + b.w - 2 - w, b.x + b.w - 3)
  then
    x = b.x + b.w - 2 - w
  end
  c:put(x, b.y, title, LABEL)
end

local function draw_poly(c, poly, style)
  if #poly == 1 then
    c:vline(poly[1].x, poly[1].y, 1, EDGE, style)
  end
  for i = 1, #poly - 1 do
    local a, b = poly[i], poly[i + 1]
    if a.x == b.x then
      c:vline(a.x, math.min(a.y, b.y), math.abs(a.y - b.y) + 1, EDGE, style)
    else
      c:hline(math.min(a.x, b.x), a.y, math.abs(a.x - b.x) + 1, EDGE, style)
    end
  end
end

local AWAY = { up = { 0, 1 }, down = { 0, -1 }, left = { 1, 0 }, right = { -1, 0 } }

-- Cardinality: glyph next to the node, the second one cell further out.
local function cardinality(c, p, kind, dir, loop)
  local glyphs = ends.cardinality(kind, dir, c.charset)
  c:put(p.x, p.y, glyphs[1], EDGE)
  if loop then
    return
  end
  c:put(p.x + AWAY[dir][1], p.y + AWAY[dir][2], glyphs[2], EDGE)
end

local function marker(c, p, kind, dir, loop)
  if ends.is_cardinality(kind) then
    cardinality(c, p, kind, dir, loop)
  elseif kind == "arrow" then
    c:arrow(p.x, p.y, dir, EDGE)
  else
    local glyph = ends.glyph(kind, dir, c.charset)
    if glyph then
      c:put(p.x, p.y, glyph, EDGE)
    end
  end
end

local function draw_lines(c, e, r)
  for _, poly in ipairs(r.polys) do
    draw_poly(c, poly, e.style)
  end
end

-- A reversed edge runs from its target (first cell) to its source (last).
local function draw_markers(c, e, r)
  local at_first, at_last = e.tail_kind or e.tail, e.head_kind or e.head
  if r.reversed then
    at_first, at_last = e.head_kind or e.head, e.tail_kind or e.tail
  end
  marker(c, r.first, at_first, r.back or route.BACKWARD[r.forward], r.loop)
  marker(c, r.last, at_last, r.forward, r.loop)
end

local function overlaps(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function free(c, spot, w, taken)
  if spot.x < 0 or spot.x + w > c.w or spot.y < 0 or spot.y >= c.h then
    return false
  end
  local rect = { x = spot.x, y = spot.y, w = w, h = 1 }
  for _, b in ipairs(taken) do
    if overlaps(rect, b) then
      return false
    end
  end
  return spot.on_line or c:is_blank(spot.x, spot.y, w)
end

-- First free spot; with none, the best spot anyway (nodes are drawn on top
-- of it only if they were drawn later, so labels never hide node text).
local function place_label(c, label, r, dir, taken)
  local lw = text.width(label)
  local spots = route.label_spots(r, lw, dir)
  for _, spot in ipairs(spots) do
    local shown = spot.on_line and (" %s "):format(label) or label
    local w = lw + (spot.on_line and 2 or 0)
    if free(c, spot, w, taken) then
      c:put(spot.x, spot.y, shown, LABEL)
      taken[#taken + 1] = { x = spot.x, y = spot.y, w = w, h = 1 }
      return
    end
  end
end

local function contains(b, n)
  return n.x >= b.x and n.y >= b.y and n.x + n.w <= b.x + b.w and n.y + n.h <= b.y + b.h
end

-- `taken` plus the boxes of clusters holding neither end of edge `info`.
local function blocked(lay, info, taken)
  local first, last = lay.nodes[info.keys[1]], lay.nodes[info.keys[#info.keys]]
  local list = vim.list_slice(taken)
  for _, b in pairs(lay.clusters) do
    if not contains(b, first) and not contains(b, last) then
      list[#list + 1] = b
    end
  end
  return list
end

local function flat(label)
  return (label:gsub("\n", " "))
end

-- Text beside an end (head_label near the target, tail_label near the source),
-- in the first free spot; none is drawn over a border or another label.
local function end_label(c, label, p, toward, taken)
  if not label or label == "" then
    return
  end
  local shown = flat(label)
  local w = text.width(shown)
  for _, spot in ipairs(ends.spots(p, toward, w)) do
    if free(c, spot, w, taken) then
      c:put(spot.x, spot.y, shown, LABEL)
      taken[#taken + 1] = { x = spot.x, y = spot.y, w = w, h = 1 }
      return
    end
  end
end

local function draw_end_labels(c, e, r, taken)
  local at_first, at_last = e.tail_label, e.head_label
  if r.reversed then
    at_first, at_last = e.head_label, e.tail_label
  end
  end_label(c, at_first, r.first, r.back or route.BACKWARD[r.forward], taken)
  end_label(c, at_last, r.last, r.forward, taken)
end

-- Room right of the layout for labels placed beside a line (trailing blanks
-- are trimmed from the output).
local function label_room(g)
  local widest = 0
  for _, e in ipairs(g.edges) do
    if e.label and e.label ~= "" then
      widest = math.max(widest, text.width(flat(e.label)) + 3)
    end
    for _, t in ipairs({ e.head_label or "", e.tail_label or "" }) do
      if t ~= "" then
        widest = math.max(widest, text.width(flat(t)) + 3)
      end
    end
  end
  return widest
end

local function draw_nodes(c, g, lay)
  local taken = {}
  for _, n in ipairs(g.nodes) do
    local b = lay.nodes[n.id]
    draw_node(c, n, b)
    taken[#taken + 1] = b
  end
  return taken
end

local function draw_edges(c, g, routes)
  for i, e in ipairs(g.edges) do
    if routes[i] then
      job.yield_point()
      draw_lines(c, e, routes[i])
    end
  end
  for i, e in ipairs(g.edges) do
    if routes[i] then
      draw_markers(c, e, routes[i])
    end
  end
end

local function draw_all_end_labels(c, g, lay, routes, taken)
  for i, e in ipairs(g.edges) do
    if routes[i] then
      local list = blocked(lay, lay.edges[i], taken)
      local before = #list
      draw_end_labels(c, e, routes[i], list)
      for k = before + 1, #list do
        taken[#taken + 1] = list[k]
      end
    end
  end
end

local function draw_edge_labels(c, g, lay, routes, taken)
  for i, e in ipairs(g.edges) do
    if routes[i] and e.label and e.label ~= "" then
      job.yield_point()
      place_label(c, flat(e.label), routes[i], g.direction, blocked(lay, lay.edges[i], taken))
    end
  end
end

---@param g table  graph as given to layout (see M.fit)
---@param lay table  graph.layout result for `g`
---@param ctx { width: integer, charset?: string }
---@return doc_preview.Output output  clipped to ctx.width
---@return integer natural  width the diagram needs; above ctx.width means clipped
function M.draw(g, lay, ctx)
  local routes = route.route(g, lay)
  local mc, mr = route.margin(routes)
  local natural = lay.width + mc + label_room(g)
  local c = canvas.new(math.min(natural, ctx.width), lay.height + mr, ctx.charset)
  for _, sg in ipairs(g.subgraphs) do
    draw_cluster(c, lay.clusters[sg.id])
  end
  local taken = draw_nodes(c, g, lay)
  draw_edges(c, g, routes)
  for _, sg in ipairs(g.subgraphs) do
    draw_title(c, routes, sg, lay.clusters[sg.id])
  end
  draw_all_end_labels(c, g, lay, routes, taken)
  draw_edge_labels(c, g, lay, routes, taken)
  return c:to_output(), natural
end

return M
