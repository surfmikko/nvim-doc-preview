-- `table` node -> Output: box grid from core/table, header and border spans,
-- one map entry per output row (doc/architecture.md 4.1). Header is source
-- line src_start, the delimiter row src_start + 1, body row i src_start + 1 + i.
local box = require("doc_preview.core.box")
local grid_layout = require("doc_preview.core.table")
local out = require("doc_preview.core.out")

local M = {}

local HEADER, BORDER, BOLD = "DocPreviewTableHeader", "DocPreviewTableBorder", "DocPreviewStrong"

-- Source line an output item maps to; border rows take the neighbouring row.
local function source_line(node, item)
  if item.rule == "top" then
    return node.src_start
  elseif item.rule == "header" then
    return node.src_start + 1
  elseif item.rule == "bottom" then
    return node.src_start + 1 + #node.rows
  end
  return item.row == 1 and node.src_start or node.src_start + item.row
end

-- Border spans over every vertical glyph (or the whole rule row).
local function border_spans(frag, n, item, glyph)
  if item.rule then
    frag:add_span(n, 0, #item.text, BORDER)
    return
  end
  local pos = item.text:find(glyph, 1, true)
  while pos do
    frag:add_span(n, pos - 1, pos - 1 + #glyph, BORDER)
    pos = item.text:find(glyph, pos + #glyph, true)
  end
end

-- Header and bold spans over the text between vertical glyphs, so bold never
-- reaches the border (bold box glyphs render with gaps in some fonts).
local function header_spans(frag, n, text, glyph)
  local from = 1
  repeat
    local pos = text:find(glyph, from, true)
    local stop = pos and pos - 1 or #text
    if stop >= from then
      frag:add_span(n, from - 1, stop, HEADER)
      frag:add_span(n, from - 1, stop, BOLD)
    end
    from = pos and pos + #glyph
  until not from
end

---@param node table table node
---@param ctx table
---@param cell_text fun(inlines: table[], line: integer): string, table[]
---@param width integer
---@return doc_preview.Output
function M.render(node, ctx, cell_text, width)
  local grid = {}
  for r, row in ipairs({ node.header, unpack(node.rows) }) do
    grid[r] = {}
    for c, cell in ipairs(row) do
      local s, ranges = cell_text(cell.inlines, node.src_start + (r == 1 and 0 or r))
      grid[r][c] = { text = s, ranges = ranges }
    end
  end
  local glyph = box.glyphs(ctx.charset).v
  local frag = out.new()
  for _, item in ipairs(grid_layout.layout(grid, node.align, width, ctx.charset)) do
    local n = frag:add_line(item.text)
    if item.row == 1 and #item.text > 0 then
      header_spans(frag, n, item.text, glyph)
    end
    for _, sp in ipairs(item.spans) do
      frag:add_span(n, sp.col_start, sp.col_end, sp.hl_group)
    end
    border_spans(frag, n, item, glyph)
    local src = source_line(node, item)
    frag:add_map(n, n, src, src)
  end
  return frag
end

return M
