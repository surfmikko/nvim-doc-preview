-- Sequence layout (mermaid/sequence_layout) -> canvas -> Output. Free of
-- Mermaid syntax (shared with PlantUML sequence diagrams). The canvas is
-- ctx.width wide at most, so the output never exceeds it; width fallbacks
-- live in mermaid/sequence.
local box = require("doc_preview.core.box")
local canvas = require("doc_preview.core.canvas")
local job = require("doc_preview.core.job")
local text = require("doc_preview.core.text")

local M = {}

local BORDER, LABEL = "DocPreviewDiagramBorder", "DocPreviewDiagramLabel"
local EDGE = "DocPreviewDiagramEdge"

local function glyphs(charset, rounded)
  local g = box.glyphs(charset)
  local r = rounded and charset ~= "ascii"
  return {
    h = g.h,
    v = g.v,
    tl = r and "╭" or g.top[1],
    tr = r and "╮" or g.top[3],
    bl = r and "╰" or g.bottom[1],
    br = r and "╯" or g.bottom[3],
  }
end

local function centered(c, x0, w, y, rows, hl)
  for i, r in ipairs(rows) do
    c:put(x0 + math.floor((w - text.width(r)) / 2), y + i - 1, r, hl)
  end
end

local function draw_participant(c, lay, col, y, charset)
  local x0 = col.x - col.hl
  c:box(x0, y, col.bw, lay.boxh, BORDER, glyphs(charset, col.kind == "actor"))
  centered(c, x0, col.bw, y + 1 + math.floor((lay.boxh - 2 - #col.lines) / 2), col.lines, LABEL)
end

local function draw_lifelines(c, lay)
  for _, col in ipairs(lay.cols) do
    c:vline(col.x, lay.life.y0, lay.life.len, BORDER, "dotted")
  end
  for _, b in ipairs(lay.bars) do
    c:vline(lay.cols[b.col].x, b.y0, b.y1 - b.y0 + 1, EDGE, "thick")
  end
end

local function draw_frame(c, lay, f)
  local d = f.depth
  c:box(d, f.y0, lay.width - 2 * d, f.y1 - f.y0 + 1, BORDER)
  for _, div in ipairs(f.dividers) do
    c:hline(d, div.y, lay.width - 2 * d, BORDER, "dotted")
    c:put(d + 2, div.y, " " .. div.text .. " ", LABEL)
  end
  c:put(d + 2, f.y0, " " .. f.text .. " ", LABEL)
end

local function draw_note(c, charset, n)
  for j = 0, n.h - 1 do
    c:put(n.x, n.y + j, (" "):rep(n.w))
  end
  c:box(n.x, n.y, n.w, n.h, BORDER, glyphs(charset))
  if n.center then
    centered(c, n.x, n.w, n.y + 1, n.lines, LABEL)
  else
    for i, r in ipairs(n.lines) do
      c:put(n.x + 2, n.y + i, r, LABEL)
    end
  end
end

-- Head glyph at x, y; `right`: the arrow points right.
local function draw_head(c, kind, x, y, right)
  if kind == "arrow" then
    c:arrow(x, y, right and "right" or "left", EDGE)
  elseif kind == "cross" then
    c:put(x, y, "x", EDGE)
  elseif kind == "async" then
    c:put(x, y, right and ")" or "(", EDGE)
  end
end

local function line_style(m)
  return m.line == "dashed" and "dotted" or "solid"
end

-- Loop right of the lifeline: out on the top row, back (head) below.
local function draw_self(c, lay, m)
  local x = lay.cols[m.from].x
  local style = line_style(m)
  c:hline(x, m.y, 4, EDGE, style)
  c:vline(x + 3, m.y, 2, EDGE, style)
  c:hline(x + 1, m.y + 1, 3, EDGE, style)
  draw_head(c, m.head, x + 1, m.y + 1, false)
  for i, r in ipairs(m.lines) do
    c:put(x + 2, m.y - #m.lines + i - 1, r, LABEL)
  end
end

local function draw_message(c, lay, m)
  if m.self then
    return draw_self(c, lay, m)
  end
  local xa, xb = lay.cols[m.from].x, lay.cols[m.to].x
  local right = xa < xb
  local x0, x1 = math.min(xa, xb) + 1, math.max(xa, xb) - 1
  c:hline(x0, m.y, x1 - x0 + 1, EDGE, line_style(m))
  draw_head(c, m.head, right and x1 or x0, m.y, right)
  for i, r in ipairs(m.lines) do
    centered(c, x0, x1 - x0 + 1, m.y - #m.lines + i - 1, { r }, LABEL)
  end
end

local function draw_items(c, lay, charset)
  for n, item in ipairs(lay.items) do
    if n % 8 == 0 then
      job.yield_point()
    end
    if item.kind == "note" then
      draw_note(c, charset, item)
    else
      draw_message(c, lay, item)
    end
  end
end

---@param lay table  result of sequence_layout.layout
---@param ctx { width: integer, charset?: string }
---@return doc_preview.Output  clipped to ctx.width
function M.draw(lay, ctx)
  local c = canvas.new(math.min(lay.width, ctx.width), lay.height, ctx.charset)
  draw_lifelines(c, lay)
  for _, f in ipairs(lay.frames) do
    draw_frame(c, lay, f)
  end
  draw_items(c, lay, ctx.charset)
  for _, col in ipairs(lay.cols) do
    draw_participant(c, lay, col, 0, ctx.charset)
    draw_participant(c, lay, col, lay.height - lay.boxh, ctx.charset)
  end
  return c:to_output()
end

return M
