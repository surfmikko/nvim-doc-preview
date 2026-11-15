-- Footnote numbering registry (doc/architecture.md 4.3). Numbers go in order
-- of first use, one per label, in a sequence separate from links.
local M = {}

function M.new()
  return { list = {}, index = {} }
end

-- Number of `label`; `line` is the source line of the block that first uses it.
---@param reg table
---@param label string
---@param line integer
---@return integer
function M.number(reg, label, line)
  local n = reg.index[label]
  if not n then
    n = #reg.list + 1
    reg.index[label] = n
    reg.list[n] = { label = label, line = line }
  end
  return n
end

return M
