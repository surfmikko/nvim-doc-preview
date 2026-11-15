-- Token-level syntax of mermaid ER diagrams (see er.lua for the parser).
local M = {}

-- Cardinality kinds (graph.model edge ends): one, zero_one, zero_many,
-- one_many. Symbols as written next to the left and the right entity.
local LEFT = { ["||"] = "one", ["|o"] = "zero_one", ["}o"] = "zero_many", ["}|"] = "one_many" }
local RIGHT = { ["||"] = "one", ["o|"] = "zero_one", ["o{"] = "zero_many", ["|{"] = "one_many" }

-- Word forms (either side), tried longest first.
local WORDS = {
  ["only one"] = "one",
  ["1"] = "one",
  ["one or zero"] = "zero_one",
  ["zero or one"] = "zero_one",
  ["zero or more"] = "zero_many",
  ["zero or many"] = "zero_many",
  ["many(0)"] = "zero_many",
  ["0+"] = "zero_many",
  ["one or more"] = "one_many",
  ["one or many"] = "one_many",
  ["many(1)"] = "one_many",
  ["1+"] = "one_many",
}
local WORD_LIST = vim.tbl_keys(WORDS)
table.sort(WORD_LIST, function(a, b)
  return #a > #b or (#a == #b and a < b)
end)

local KEYS = { PK = true, FK = true, UK = true }

-- Entity name at `pos`: quoted, or word characters and inner hyphens.
-- Returns name, position after it.
---@return string|nil name
---@return integer|nil pos
function M.name(s, pos)
  local q, np = s:match('^"([^"]+)"()', pos)
  if q then
    return q, np
  end
  local w, wp = s:match("^([%w_][%w_%-]*)()", pos)
  if w then
    return w, wp
  end
end

local function skip_ws(s, pos)
  return s:find("%S", pos) or #s + 1
end

-- Cardinality word at `pos`, followed by whitespace. Returns kind, next pos.
local function word(s, pos)
  for _, w in ipairs(WORD_LIST) do
    if s:sub(pos, pos + #w - 1) == w and s:match("^%s", pos + #w) then
      return WORDS[w], skip_ws(s, pos + #w)
    end
  end
end

-- `|o--o{` or `one or zero to many` / `... optionally to ...` at `pos`.
-- Returns tail kind (left entity), head kind (right entity), identifying,
-- next pos.
local function connector(s, pos)
  local l, line, r, np = s:match("^(%S%S)([%-%.][%-%.])(%S%S)%s*()", pos)
  if l and LEFT[l] and RIGHT[r] and (line == "--" or line == "..") then
    return LEFT[l], RIGHT[r], line == "--", np
  end
  local tail, tp = word(s, pos)
  if not tail then
    return nil
  end
  local identifying = true
  local rest = s:match("^optionally to%s+()", tp)
  if rest then
    identifying = false
  else
    rest = s:match("^to%s+()", tp)
  end
  if not rest then
    return nil
  end
  local head, hp = word(s, rest)
  if head then
    return tail, head, identifying, hp
  end
end

-- `A ||--o{ B : label`. Returns { from, to, tail_kind, head_kind,
-- identifying, label } or nil when the line is not a relationship.
---@param s string
function M.relation(s)
  local from, pos = M.name(s, 1)
  if not from then
    return nil
  end
  local tail, head, identifying, np = connector(s, skip_ws(s, pos))
  if not tail then
    return nil
  end
  local to, after = M.name(s, np)
  if not to then
    return nil
  end
  local rest = s:sub(after):match("^%s*(.-)%s*$")
  local label
  if rest ~= "" then
    label = rest:match("^:%s*(.-)$")
    if not label then
      return nil
    end
    label = label:match('^"(.*)"$') or label
  end
  return {
    from = from,
    to = to,
    tail_kind = tail,
    head_kind = head,
    identifying = identifying,
    label = label ~= "" and label or nil,
  }
end

-- `type name PK, FK "comment"`. Returns { type, name, keys = {}, comment? }
-- or nil.
---@param s string
function M.attribute(s)
  local ty, name, rest = s:match("^(%S+)%s+(%S+)%s*(.-)$")
  if not ty then
    return nil
  end
  local a = { type = ty, name = name, keys = {} }
  while true do
    local key, after = rest:match("^(%u%u)%s*,?%s*(.-)$")
    if not key or not KEYS[key] then
      break
    end
    a.keys[#a.keys + 1] = key
    rest = after
  end
  if rest ~= "" then
    a.comment = rest:match('^"(.*)"$')
    if not a.comment then
      return nil
    end
  end
  return a
end

return M
