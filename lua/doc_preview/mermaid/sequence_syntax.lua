-- Mermaid sequence diagram statements (one statement per call, no state).
-- Each parser returns a table, or nil when the statement is not of its kind.
local M = {}

-- Longest operators first: `-->>` must win over `-->`.
local ARROWS = {
  { "-->>", "dashed", "arrow" },
  { "--x", "dashed", "cross" },
  { "--)", "dashed", "async" },
  { "->>", "solid", "arrow" },
  { "-->", "dashed", "open" },
  { "-x", "solid", "cross" },
  { "-)", "solid", "async" },
  { "->", "solid", "open" },
}

---@param s string  label or message text
---@return string  `<br/>` as newline, trimmed
function M.clean(s)
  return (s:gsub("<[bB][rR]%s*/?>", "\n"):match("^%s*(.-)%s*$"))
end

-- The message for arrow `a` at the start of `rest`, or nil when its target is malformed.
local function after_arrow(from, rest, a)
  local mark, to, tail = rest:sub(#a[1] + 1):match("^%s*([+-]?)%s*([%w_]+)%s*(.*)$")
  local text = tail and tail:match("^:%s*(.*)$")
  if not (to and (tail == "" or text)) then
    return nil
  end
  return {
    kind = "message",
    from = from,
    to = to,
    line = a[2],
    head = a[3],
    text = M.clean(text or ""),
    activate = mark == "+" or nil,
    deactivate = mark == "-" or nil,
  }
end

-- `A->>+B: text`; the `+`/`-` after the operator is the activation shorthand.
function M.message(stmt)
  local from, rest = stmt:match("^([%w_]+)%s*(%-.*)$")
  if not from then
    return nil
  end
  for _, a in ipairs(ARROWS) do
    if rest:sub(1, #a[1]) == a[1] then
      local msg = after_arrow(from, rest, a)
      if msg then
        return msg
      end
    end
  end
  return nil
end

-- `participant A`, `participant A as Alice`, `actor B as Bob`; `create` prefix allowed.
function M.participant(stmt)
  stmt = stmt:gsub("^create%s+", "")
  local kind, id, label = stmt:match("^(%a+)%s+([%w_]+)%s+as%s+(.+)$")
  if not kind then
    kind, id = stmt:match("^(%a+)%s+([%w_]+)%s*$")
  end
  if kind ~= "participant" and kind ~= "actor" then
    return nil
  end
  return { id = id, kind = kind, label = label and M.clean(label) or nil }
end

-- `Note left of A: x`, `note over A,B: x`.
function M.note(stmt)
  local kw, side, ids, text = stmt:match("^(%a+)%s+(%a+)%s+of%s+([%w_]+)%s*:%s*(.*)$")
  if not kw then
    kw, side, ids, text = stmt:match("^(%a+)%s+(over)%s+([%w_,%s]+)%s*:%s*(.*)$")
  end
  if
    (kw ~= "Note" and kw ~= "note") or not (side == "left" or side == "right" or side == "over")
  then
    return nil
  end
  local targets = {}
  for id in ids:gmatch("[%w_]+") do
    targets[#targets + 1] = id
  end
  return { kind = "note", side = side, targets = targets, text = M.clean(text) }
end

-- `autonumber`, `autonumber off`, `autonumber 10`, `autonumber 10 5`.
function M.autonumber(stmt)
  local arg = stmt:match("^autonumber%s*(.-)$")
  if not arg then
    return nil
  end
  if arg == "off" then
    return { kind = "autonumber", off = true }
  end
  local start, step = arg:match("^(%d+)%s*(%d*)$")
  if arg ~= "" and not start then
    return nil
  end
  return { kind = "autonumber", start = tonumber(start), step = tonumber(step) }
end

-- `activate A` / `deactivate A`.
function M.activation(stmt)
  local kw, id = stmt:match("^(%a+)%s+([%w_]+)$")
  if kw == "activate" or kw == "deactivate" then
    return { kind = kw, id = id }
  end
  return nil
end

local BLOCKS = {
  loop = true,
  alt = true,
  opt = true,
  par = true,
  critical = true,
  ["break"] = true,
  rect = true,
  box = true,
}
-- Continuation keyword -> the block type it continues.
local SECTIONS = { ["else"] = "alt", ["and"] = "par", option = "critical" }

-- `loop text`, `alt`, `rect rgb(0,0,0)`: block type and label.
function M.block_open(stmt)
  local kw, label = stmt:match("^(%a+)%s*(.-)$")
  if BLOCKS[kw] then
    return kw, M.clean(label)
  end
  return nil
end

-- `else text`, `and`, `option text`: section keyword, owning block type, label.
function M.section(stmt)
  local kw, label = stmt:match("^(%a+)%s*(.-)$")
  if SECTIONS[kw] then
    return kw, SECTIONS[kw], M.clean(label)
  end
  return nil
end

-- Statements accepted and ignored (nothing to draw).
local IGNORED = {
  title = true,
  accTitle = true,
  accDescr = true,
  link = true,
  links = true,
  properties = true,
  details = true,
  destroy = true,
}

function M.ignored(stmt)
  return IGNORED[stmt:match("^(%a+)")] == true
end

return M
