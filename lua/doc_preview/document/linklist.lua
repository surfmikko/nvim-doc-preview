-- Link numbering and the "Links" section (doc/architecture.md 4.3). Numbers
-- go in order of first use, one per distinct target. Footnotes (0016) have
-- their own sequence, so they never renumber links.
local out = require("doc_preview.core.out")
local text = require("doc_preview.core.text")

local M = {}

M.TITLE = "Links"

function M.new()
  return { list = {}, index = {} }
end

-- Number of `target`; `line` is the source line of the block that first uses it.
---@param reg table
---@param target string
---@param line integer
---@return integer
function M.number(reg, target, line)
  local n = reg.index[target]
  if not n then
    n = #reg.list + 1
    reg.index[target] = n
    reg.list[n] = { target = target, line = line }
  end
  return n
end

---@param reg table
---@param width integer
---@return doc_preview.Output|nil  nil when no link was used
function M.section(reg, width)
  if #reg.list == 0 then
    return nil
  end
  local frag = out.new()
  frag:add_line(M.TITLE)
  frag:add_span(1, 0, #M.TITLE, "DocPreviewH2")
  frag:add_map(1, 1, reg.list[1].line, reg.list[1].line)
  for n, entry in ipairs(reg.list) do
    local marker = "[" .. n .. "]"
    local first = #frag.lines + 1
    for _, line in ipairs(text.wrap(marker .. " " .. entry.target, width)) do
      frag:add_line(line)
    end
    frag:add_span(first, 0, #marker, "DocPreviewLinkMark")
    frag:add_map(first, #frag.lines, entry.line, entry.line)
  end
  return frag
end

return M
