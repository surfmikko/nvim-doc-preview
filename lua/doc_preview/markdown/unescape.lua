-- Backslash escapes and character references, shared by the inline pass and
-- the link destination/title parser (doc/references.md: behaviour only).
local entities = require("doc_preview.markdown.entities")

local M = {}

local function utf8_char(cp)
  if cp == 0 or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF) then
    cp = 0xFFFD
  end
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)
  elseif cp < 0x10000 then
    return string.char(
      0xE0 + math.floor(cp / 4096),
      0x80 + math.floor(cp / 64) % 64,
      0x80 + cp % 64
    )
  end
  return string.char(
    0xF0 + math.floor(cp / 262144),
    0x80 + math.floor(cp / 4096) % 64,
    0x80 + math.floor(cp / 64) % 64,
    0x80 + cp % 64
  )
end

-- Text for the body of `&body;`, or nil when it is not a reference.
function M.decode(body)
  local hex = body:match("^#[xX](%x+)$")
  local dec = body:match("^#(%d+)$")
  if hex and #hex <= 6 then
    return utf8_char(tonumber(hex, 16))
  elseif dec and #dec <= 7 then
    return utf8_char(tonumber(dec))
  end
  return entities[body]
end

---@param s string
---@return string s with escapes and references resolved
function M.unescape(s)
  local res, i = {}, 1
  while i <= #s do
    local c, nxt = s:sub(i, i), s:sub(i + 1, i + 1)
    local body = c == "&" and s:match("^&([#%w]+);", i)
    local decoded = body and M.decode(body)
    if c == "\\" and nxt:match("^%p$") then
      res[#res + 1], i = nxt, i + 2
    elseif decoded then
      res[#res + 1], i = decoded, i + #body + 2
    else
      res[#res + 1], i = c, i + 1
    end
  end
  return table.concat(res)
end

return M
