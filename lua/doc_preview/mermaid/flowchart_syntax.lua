-- Flowchart statement pieces: node (id plus shape text) and edge operators.
-- Behaviour read from the mermaid.js flowchart docs (doc/references.md);
-- nothing ported. Functions return nil when the text does not parse.
local model = require("doc_preview.graph.model")

local M = {}

-- open, close, shape; longer openers first. Others fall back to rect.
local SHAPES = {
  { "((", "))", "circle" },
  { "([", "])", "stadium" },
  { "[[", "]]", "subroutine" },
  { "[(", ")]", "cylinder" },
  { "{{", "}}", "hexagon" },
  { "[", "]", "rect" },
  { "(", ")", "round" },
  { "{", "}", "rhombus" },
  { ">", "]", "rect" },
}

local HEADS = { [">"] = "arrow", o = "circle", x = "cross", [""] = "none" }
local TAILS = { ["<"] = "arrow", o = "circle", x = "cross" }

local function trim(s)
  return s:match("^%s*(.-)%s*$")
end

-- Label text: strip quotes, markdown-string backticks, `<br/>` to newline.
function M.clean(s)
  s = trim(s)
  local quoted = s:match('^"(.*)"$')
  if quoted then
    s = quoted:match("^`(.*)`$") or quoted
  end
  return (s:gsub("<br%s*/?>", "\n"))
end

-- Text up to `close`; a quoted text may contain the closer.
local function read_text(s, pos, close)
  local from = s:find("%S", pos) or pos
  if s:sub(from, from) == '"' then
    local q = s:find('"', from + 1, true)
    if not q then
      return nil
    end
    local a, e = s:find(close, q + 1, true)
    if a and s:sub(q + 1, a - 1):match("^%s*$") then
      return s:sub(from, q), e + 1
    end
    return nil
  end
  local a, e = s:find(close, pos, true)
  if a then
    return s:sub(pos, a - 1), e + 1
  end
end

local function opener(s, pos)
  for _, sh in ipairs(SHAPES) do
    if s:sub(pos, pos + #sh[1] - 1) == sh[1] then
      return sh
    end
  end
end

-- `[/text/]`, `[\text\]` and friends are drawn as rect with the slashes removed.
local function strip_slashes(text)
  return text:match("^%s*[/\\](.-)[/\\]%s*$") or text
end

-- Parse `id` plus optional shape at `pos`, declare it in `g`.
---@return string|nil id
---@return integer|nil next position
function M.node(g, s, pos)
  local id, after = s:match("^([%w_]+)()", pos)
  if not id then
    return nil
  end
  local sh = opener(s, after)
  if not sh then
    model.add_node(g, id)
    return id, after
  end
  local text, np = read_text(s, after + #sh[1], sh[2])
  if not text then
    return nil
  end
  if sh[1] == "[" and not text:match('^%s*"') then
    text = strip_slashes(text)
  end
  model.add_node(g, id, M.clean(text), sh[3])
  return id, np
end

-- Rank length: `-->` is 1, `--->` 2; an open link `---` is 1, `----` 2.
local function rank(run, head, base)
  return math.max(head == "" and run - base - 1 or run - base, 1)
end

-- Operator without text; table of style, head char, length, next position.
local function plain_op(s, pos)
  local dashes, h, np = s:match("^(%-%-+)([>ox]?)()", pos)
  if dashes and (h ~= "" or #dashes >= 3) then
    return "solid", h, rank(#dashes, h, 1), np
  end
  local eq, he, ne = s:match("^(==+)([>ox]?)()", pos)
  if eq and (he ~= "" or #eq >= 3) then
    return "thick", he, rank(#eq, he, 1), ne
  end
  local dots, hd, nd = s:match("^%-(%.+)%-([>ox]?)()", pos)
  if dots then
    return "dotted", hd, #dots, nd
  end
end

-- `-- text -->`, `-. text .->`, `== text ==>`: opener, closer pattern, style.
local TEXT_OPS = {
  { "^%-%-%s+()", "%-%-+", "solid" },
  { "^%-%.%s+()", "%.+%-", "dotted" },
  { "^==%s+()", "==+", "thick" },
}

local function text_op(s, pos)
  for _, op in ipairs(TEXT_OPS) do
    local from = s:match(op[1], pos)
    local a, e
    if from then
      a, e = s:find(op[2], from)
    end
    if a then
      local h = s:match("^[>ox]?", e + 1)
      local run = e - a + 1
      if op[3] == "dotted" then
        run = run - 1
      end
      if op[3] == "dotted" or h ~= "" or run >= 3 then
        local len = op[3] == "dotted" and run or rank(run, h, 1)
        return op[3], h, len, e + 1 + #h, M.clean(s:sub(from, a - 1))
      end
    end
  end
end

-- Parse an edge operator (with optional `|label|`) at `pos`.
---@return table|nil edge  { style, head, tail, length, label? }
---@return integer|nil next position
function M.edge(s, pos)
  local tail = "none"
  if TAILS[s:sub(pos, pos)] and s:sub(pos + 1, pos + 1):match("[%-=]") then
    tail = TAILS[s:sub(pos, pos)]
    pos = pos + 1
  end
  local style, h, length, np, label = text_op(s, pos)
  if not style then
    style, h, length, np = plain_op(s, pos)
  end
  if not style then
    return nil
  end
  local pipe = s:match("^%s*|()", np)
  if pipe then
    local text, after = read_text(s, pipe, "|")
    if not text then
      return nil
    end
    label, np = M.clean(text), after
  end
  return { style = style, head = HEADS[h], tail = tail, length = length, label = label }, np
end

return M
