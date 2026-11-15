-- Mermaid engine: `render(lines, ctx) -> Output`, always returns an
-- Output (doc/diagram-model.md 1). Unknown types, empty input, raising
-- or invalid type modules all end in a core/errbox listing the source.
local errbox = require("doc_preview.core.errbox")
local out = require("doc_preview.core.out")
local registry = require("doc_preview.mermaid.registry")
local source = require("doc_preview.mermaid.source")

local M = {}

registry.register("flowchart", require("doc_preview.mermaid.flowchart"))
registry.register("graph", require("doc_preview.mermaid.flowchart"))
registry.register("sequenceDiagram", require("doc_preview.mermaid.sequence"))
registry.register("classDiagram", require("doc_preview.mermaid.class"))
registry.register("classDiagram-v2", require("doc_preview.mermaid.class"))
registry.register("stateDiagram", require("doc_preview.mermaid.state"))
registry.register("stateDiagram-v2", require("doc_preview.mermaid.state"))
registry.register("erDiagram", require("doc_preview.mermaid.er"))
registry.register("pie", require("doc_preview.mermaid.pie"))
registry.register("gantt", require("doc_preview.mermaid.gantt"))

---@param lines string[]
---@return string|nil name  first word of the first content line
function M.detect(lines)
  local l = lines[source.first_content(lines)]
  return l and l:match("^%s*([%w_%-]+)")
end

local function fail(lines, ctx, title)
  return errbox.render(lines, ctx, "mermaid: " .. title)
end

---@param lines string[]
---@param ctx { width: integer, charset?: string }
---@return doc_preview.Output
function M.render(lines, ctx)
  local name = M.detect(lines)
  if not name then
    return fail(lines, ctx, "empty diagram")
  end
  local mod = registry.get(name)
  if not mod then
    return fail(lines, ctx, ('unsupported diagram type "%s"'):format(name))
  end
  local ok, result = pcall(mod.render, lines, ctx)
  if not ok then
    local msg = tostring(result):gsub("^[^\n]-:%d+: ", "")
    return fail(lines, ctx, name .. ": " .. msg)
  end
  if not out.valid(result, ctx.width) then
    return fail(lines, ctx, name .. ": invalid output")
  end
  return result
end

return M
