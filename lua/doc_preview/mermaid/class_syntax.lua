-- Token-level syntax of mermaid class diagrams (see class.lua for the parser).
local M = {}

-- Relation end tokens to graph.model end kinds.
local TAILS = {
  ["<|"] = "triangle",
  ["*"] = "diamond_filled",
  ["o"] = "diamond",
  ["<"] = "arrow",
  [""] = "none",
}
local HEADS = {
  ["|>"] = "triangle",
  ["*"] = "diamond_filled",
  ["o"] = "diamond",
  [">"] = "arrow",
  [""] = "none",
}

-- `~T~` generics shown as `<T>`.
---@param s string
function M.generics(s)
  return (s:gsub("~([^~]*)~", "<%1>"))
end

-- Class name at `pos`: backquoted or word characters with optional `~T~`
-- and `:::css` suffix. Returns id, display label, next position.
---@return string|nil id
---@return string|nil label
---@return integer|nil pos
function M.name(s, pos)
  local q, np = s:match("^`([^`]+)`()", pos)
  if q then
    return q, q, np
  end
  local word, after = s:match("^([%w_%.%$]+)()", pos)
  if not word then
    return nil
  end
  local gen, gen_end = s:match("^(~[^~]*~)()", after)
  gen_end = gen_end or after
  local css = s:match("^:::[%w_%-]+()", gen_end)
  return word, word .. M.generics(gen or ""), css or gen_end
end

local function skip_ws(s, pos)
  return s:find("%S", pos) or #s + 1
end

-- Optional `"card"` at `pos`: text (or nil) and the position after it.
local function cardinality(s, pos)
  local c, np = s:match('^"([^"]*)"%s*()', pos)
  if c then
    return c, np
  end
  return nil, pos
end

-- Relation operator word such as `<|--` or `..>`: tail kind, style, head
-- kind and the position after it, or nil.
local function operator(s, pos)
  local tok, np = s:match("^(%S+)%s*()", pos)
  if not tok then
    return nil
  end
  local tail, line, head = tok:match("^([<|*o]*)([%-%.]+)([|>*o]*)$")
  if not tail or (line ~= "--" and line ~= "..") or not TAILS[tail] or not HEADS[head] then
    return nil
  end
  return TAILS[tail], line == ".." and "dotted" or "solid", HEADS[head], np
end

-- Optional `: label` after a relation: ok (false when the text is not a
-- label) and the label.
local function trailing_label(s, pos)
  local rest = s:sub(pos):match("^%s*(.-)%s*$")
  if rest == "" then
    return true, nil
  end
  local label = rest:match("^:%s*(.*)$")
  label = label and (label:match('^"(.*)"$') or label)
  return label ~= nil, label
end

-- `A "1" <|-- "*" B : label`. Returns a relation
-- { from, to, from_label, to_label, tail_kind, head_kind, style, tail_card,
-- head_card, label } or nil when the line is not a relation.
---@param s string
function M.relation(s)
  local from, from_label, pos = M.name(s, 1)
  if not from then
    return nil
  end
  pos = skip_ws(s, pos)
  local tail_card, head_card
  tail_card, pos = cardinality(s, pos)
  local tail_kind, style, head_kind, np = operator(s, pos)
  if not style then
    return nil
  end
  head_card, np = cardinality(s, np)
  local to, to_label, after = M.name(s, np)
  if not to then
    return nil
  end
  local ok, label = trailing_label(s, after)
  if not ok then
    return nil
  end
  return {
    from = from,
    from_label = from_label,
    to = to,
    to_label = to_label,
    tail_kind = tail_kind,
    head_kind = head_kind,
    style = style,
    tail_card = tail_card,
    head_card = head_card,
    label = label and label ~= "" and M.generics(label) or nil,
  }
end

return M
