-- Facts projection for pie pairs (doc/testing.md 3.2): a parsed pie as plain
-- lines, one fact per line.
--   pie showData=true title "Pets"
--   slice "Dogs" value=386 pct=39
local M = {}

local function quote(s)
  return '"' .. s .. '"'
end

---@param pie table  from pie.parse
---@return string
function M.project(pie)
  local head = "pie showData=" .. tostring(pie.show_data)
  local out = { pie.title and (head .. " title " .. quote(pie.title)) or head }
  for _, s in ipairs(pie.slices) do
    out[#out + 1] = ("slice %s value=%s pct=%d"):format(quote(s.label), s.raw, s.pct)
  end
  return table.concat(out, "\n")
end

return M
