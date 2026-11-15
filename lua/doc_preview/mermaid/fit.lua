-- Shared width policy of the graph-based mermaid diagrams (flowchart, class):
-- compact spacing, then top-down for LR/RL, then the boxed source with a
-- note (doc/diagram-model.md 1). Below the errbox minimum width the clipped
-- drawing is returned (nothing readable fits anyway).
local draw = require("doc_preview.graph.draw")
local errbox = require("doc_preview.core.errbox")
local layout = require("doc_preview.graph.layout")

local M = {}

-- Draw `g` (labels cut to the width); second result: it fits ctx.width.
local function attempt(g, ctx, compact)
  local fg = draw.fit(g, ctx.width)
  local o, natural = draw.draw(fg, layout.layout(fg, { compact = compact }), ctx)
  return o, natural <= ctx.width
end

local function fitting(g, ctx)
  local o, ok = attempt(g, ctx, ctx.compact)
  if ok then
    return o
  end
  o, ok = attempt(g, ctx, true)
  if not ok and (g.direction == "LR" or g.direction == "RL") then
    o, ok = attempt(vim.tbl_extend("force", g, { direction = "TD" }), ctx, true)
  end
  return ok and o or nil, o
end

---@param g table graph.model
---@param lines string[] source, shown boxed when nothing fits
---@param ctx { width: integer, charset?: string, compact?: boolean }
---@return doc_preview.Output
function M.render(g, lines, ctx)
  local o, clipped = fitting(g, ctx)
  if o then
    return o
  end
  if ctx.width < 5 then
    return clipped
  end
  return errbox.render(lines, ctx, ("diagram wider than %d columns"):format(ctx.width))
end

return M
