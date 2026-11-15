-- Link syntax helpers (pure string functions): labels, destinations, titles,
-- autolinks and link reference definitions. Positions are 1-based byte
-- indexes. Reference: CommonMark spec sections "Links", "Autolinks", "Link
-- reference definitions"; behaviour only, no code copied (doc/references.md).
-- Limit: labels fold ASCII case only.
local unescape = require("doc_preview.markdown.unescape")

local M = {}

local MAX_LABEL = 999

-- Index after blanks and at most one line ending (plus the blanks after it).
function M.skip_ws(s, p)
  p = s:match("^[ \t]*()", p)
  if s:sub(p, p) == "\n" then
    p = s:match("^[ \t]*()", p + 1)
  end
  return p
end

local function escaped(s, i)
  return s:sub(i, i) == "\\" and s:sub(i + 1, i + 1):match("^%p$") ~= nil
end

---@param s string
---@param p integer  index of "["
---@return string|nil raw  label text without the brackets
---@return integer|nil stop  index after "]"
function M.label(s, p)
  if s:sub(p, p) ~= "[" then
    return nil
  end
  local i = p + 1
  while s:sub(i, i) ~= "]" do
    local c = s:sub(i, i)
    if c == "" or c == "[" then
      return nil
    end
    i = i + (escaped(s, i) and 2 or 1)
  end
  local raw = s:sub(p + 1, i - 1)
  if #raw > MAX_LABEL or not raw:match("%S") then
    return nil
  end
  return raw, i + 1
end

---@param raw string
---@return string key  trimmed, whitespace collapsed, lowercased
function M.normalize(raw)
  return (raw:lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local function angle_destination(s, p)
  local i = p + 1
  while s:sub(i, i) ~= ">" do
    local c = s:sub(i, i)
    if c == "" or c == "\n" or c == "<" then
      return nil
    end
    i = i + (escaped(s, i) and 2 or 1)
  end
  return unescape.unescape(s:sub(p + 1, i - 1)), i + 1
end

local function ends_bare(c, depth)
  return c == "" or c:match("^[%c ]$") ~= nil or (c == ")" and depth == 0)
end

local function bare_destination(s, p)
  local i, depth = p, 0
  while true do
    local c = s:sub(i, i)
    if escaped(s, i) then
      i = i + 2
    elseif ends_bare(c, depth) then
      break
    else
      depth = depth + (c == "(" and 1 or c == ")" and -1 or 0)
      i = i + 1
    end
  end
  if depth ~= 0 then
    return nil
  end
  return unescape.unescape(s:sub(p, i - 1)), i
end

-- Destination at `p`: `<...>` or a run without blanks and with balanced
-- parentheses (possibly empty). Returns the text and the index after it.
function M.destination(s, p)
  if s:sub(p, p) == "<" then
    return angle_destination(s, p)
  end
  return bare_destination(s, p)
end

local CLOSE = { ['"'] = '"', ["'"] = "'", ["("] = ")" }

-- Title at `p` ("..." or '...' or (...)). Returns the text and the index after it.
function M.title(s, p)
  local open = s:sub(p, p)
  local close = CLOSE[open]
  if not close then
    return nil
  end
  local i = p + 1
  while s:sub(i, i) ~= close do
    local c = s:sub(i, i)
    if c == "" or (open == "(" and c == "(") then
      return nil
    end
    i = i + (escaped(s, i) and 2 or 1)
  end
  return unescape.unescape(s:sub(p + 1, i - 1)), i + 1
end

-- `(dest "title")` at `p` (the "("). Returns dest, title|nil, index after ")".
function M.inline_tail(s, p)
  local start = M.skip_ws(s, p + 1)
  local dest, q = M.destination(s, start)
  if not dest then
    return nil
  end
  local t = M.skip_ws(s, q)
  local title
  if t > q and CLOSE[s:sub(t, t)] then
    title, t = M.title(s, t)
    if not title then
      return nil
    end
    t = M.skip_ws(s, t)
  end
  if s:sub(t, t) ~= ")" then
    return nil
  end
  return dest, title, t + 1
end

local function is_email(body)
  local domain = body:match("^[%w.!#$%%&'*+/=?^_`{|}~%-]+@(.+)$")
  if not domain then
    return false
  end
  for part in (domain .. "."):gmatch("([^.]*)%.") do
    if not part:match("^%w[%w%-]*$") or part:sub(-1) == "-" or #part > 63 then
      return false
    end
  end
  return true
end

-- `<...>` autolink at `i`. Returns target, shown text, index after ">".
function M.autolink(s, i)
  local body = s:match("^<([^%c <>]+)>", i)
  if not body then
    return nil
  end
  local stop = i + #body + 2
  local scheme = body:match("^(%a[%w+.%-]*):")
  if scheme and #scheme >= 2 and #scheme <= 32 then
    return body, body, stop
  elseif is_email(body) then
    return "mailto:" .. body, body, stop
  end
end

-- Index after the end of the line that holds only blanks from `p`, or nil.
local function line_end(s, p)
  local stop = s:match("^[ \t]*\n()", p)
  if stop then
    return stop
  elseif s:match("^[ \t]*$", p) then
    return #s + 1
  end
end

-- Definition at `p` (start of a line). Returns key, dest, title|nil, stop
-- (index at the start of the next line, or #s + 1).
function M.definition(s, p)
  local raw, q = M.label(s, p)
  if not raw or s:sub(q, q) ~= ":" then
    return nil
  end
  local start = M.skip_ws(s, q + 1)
  local dest, after = M.destination(s, start)
  if not dest or after == start then
    return nil
  end
  local t = M.skip_ws(s, after)
  local title, stop
  if t > after then
    local text, r = M.title(s, t)
    stop = text and line_end(s, r)
    title = stop and text
  end
  stop = stop or line_end(s, after)
  if not stop then
    return nil
  end
  return M.normalize(raw), dest, title, stop
end

-- Strip leading definitions from paragraph `text`, adding unseen labels to
-- `refs` ({ key = { target, title } }). Returns the rest of the text and the
-- number of lines consumed.
function M.extract(text, refs)
  local pos, consumed = 1, 0
  while pos <= #text do
    local key, dest, title, stop = M.definition(text, pos)
    if not key then
      break
    end
    refs[key] = refs[key] or { target = dest, title = title }
    local seg = text:sub(pos, stop - 1)
    local _, newlines = seg:gsub("\n", "")
    consumed = consumed + newlines + (seg:sub(-1) == "\n" and 0 or 1)
    pos = stop
  end
  return text:sub(pos), consumed
end

return M
