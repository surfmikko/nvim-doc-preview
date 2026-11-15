-- Diagram type name -> module with `render(lines, ctx) -> Output`
-- (doc/diagram-model.md 1). Types register themselves from mermaid/init.
local M = {}

local types = {}

---@param name string  case-sensitive first word of the diagram, e.g. "flowchart"
---@param mod { render: fun(lines: string[], ctx: table): table }
function M.register(name, mod)
  types[name] = mod
end

function M.unregister(name)
  types[name] = nil
end

---@return table|nil
function M.get(name)
  return types[name]
end

return M
