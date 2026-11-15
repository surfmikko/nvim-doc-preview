-- Footnote markers and the "Footnotes" section (doc/architecture.md 4.3).
-- A marker is "[^n]"; a reference without a definition stays literal text.
local footnotes = require("doc_preview.document.footnotes")
local out = require("doc_preview.core.out")

local M = {}

M.TITLE = "Footnotes"
M.MARKER_GROUP = "DocPreviewFootnoteRef"

-- label -> footnote_def over the whole tree, nested blocks included; the
-- first definition of a label wins.
---@param children table[]
---@param defs? table
---@return table
function M.collect(children, defs)
  defs = defs or {}
  for _, node in ipairs(children) do
    if node.kind == "footnote_def" and not defs[node.label] then
      defs[node.label] = node
    end
    if node.children then
      M.collect(node.children, defs)
    end
  end
  return defs
end

-- Definitions render only in the section, never in place.
function M.without_defs(children)
  local kept = {}
  for _, node in ipairs(children) do
    if node.kind ~= "footnote_def" then
      kept[#kept + 1] = node
    end
  end
  return kept
end

function M.setup(ctx, doc)
  ctx.footnotes = footnotes.new()
  ctx.footnote_defs = M.collect(doc.children)
end

-- Marker text and group for a reference, or the literal text and nil group.
---@return string text
---@return string|nil group
function M.marker(ctx, label, line)
  if not ctx.footnote_defs[label] then
    return "[^" .. label .. "]", nil
  end
  return "[^" .. footnotes.number(ctx.footnotes, label, line) .. "]", M.MARKER_GROUP
end

-- Map entry for every row that no block entry covers (blank rows between
-- body blocks), then entries in ascending order.
local function cover(frag, def)
  local covered = {}
  for _, m in ipairs(frag.map) do
    for row = m.out_start, m.out_end do
      covered[row] = true
    end
  end
  for row = 1, #frag.lines do
    if not covered[row] then
      frag:add_map(row, row, def.src_start, def.src_end)
    end
  end
  table.sort(frag.map, function(a, b)
    return a.out_start < b.out_start
  end)
end

-- `render_entry(def, marker, ctx)` renders a definition body hanging under
-- `marker`. Bodies may reference more footnotes; the loop picks those up.
---@return doc_preview.Output|nil  nil when no footnote was used
function M.section(ctx, render_entry)
  local reg = ctx.footnotes
  if #reg.list == 0 then
    return nil
  end
  local frag = out.new()
  local first = ctx.footnote_defs[reg.list[1].label]
  frag:add_line(M.TITLE)
  frag:add_span(1, 0, #M.TITLE, "DocPreviewH2")
  frag:add_map(1, 1, first.src_start, first.src_start)
  local n = 1
  while n <= #reg.list do
    local def = ctx.footnote_defs[reg.list[n].label]
    local entry = render_entry(def, n .. ". ", ctx)
    cover(entry, def)
    frag:append(entry)
    n = n + 1
  end
  return frag
end

return M
