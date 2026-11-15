-- Token-level syntax of mermaid state diagrams (see state.lua for the parser).
local M = {}

M.START_END = "[*]"

-- A state reference: `[*]` or an identifier, with an optional `:::css`
-- suffix dropped. Returns the id or nil.
---@param s string
---@return string|nil
function M.ref(s)
  s = s:match("^%s*(.-)%s*$"):gsub(":::[%w_%-]+$", "")
  if s == M.START_END or s:match("^[%w_%.]+$") then
    return s
  end
end

-- `A --> B`, `A --> B : label`. Returns from, to, label (label may be nil)
-- or nil when the line is not a transition.
---@param s string
function M.transition(s)
  local left, right = s:match("^(.-)%s*%-%->%s*(.+)$")
  if not left then
    return nil
  end
  right = right:gsub("^([%w_%.%[%]%*]+):::[%w_%-]+", "%1")
  local target, label = right:match("^(.-)%s*:%s*(.*)$")
  local from, to = M.ref(left), M.ref(target or right)
  if not from or not to then
    return nil
  end
  return from, to, (label and label ~= "") and label or nil
end

-- `state "Long name" as id`, `state id`, `state id <<choice>>`,
-- `state "Long" as id {`, `state id {`. Returns
-- { id, label?, kind?, open } or nil.
---@param rest string  text after `state`
function M.declaration(rest)
  local label, tail = rest:match('^"([^"]*)"%s+as%s+(.+)$')
  tail = tail or rest
  local open = false
  local body = tail:match("^(.-)%s*{$")
  if body then
    tail, open = body, true
  end
  local id, kind = tail:match("^(%S+)%s+<<(%a+)>>$")
  id = M.ref(id or tail)
  if not id or id == M.START_END then
    return nil
  end
  return { id = id, label = label, kind = kind, open = open }
end

-- `note left of X : text`, `note right of X`, `note over X : text`.
-- Returns target, text (nil for the block form) or nil.
---@param stmt string
function M.note(stmt)
  local target, rest = stmt:match("^note%s+%a+%s+of%s+(%S+)%s*(.*)$")
  if not target then
    target, rest = stmt:match("^note%s+over%s+(%S+)%s*(.*)$")
  end
  target = target and M.ref(target)
  if not target then
    return nil
  end
  local text = rest:match("^:%s*(.*)$")
  if not text and rest ~= "" then
    return nil
  end
  return target, text
end

---@param s string
function M.text(s)
  return (s:gsub("\\n", "\n"):gsub("<br%s*/?>", "\n"))
end

return M
