-- Markdown HTML blocks (start conditions 1-7) and the shared open/closing
-- tag matcher. Contents are never interpreted: block lines are collected
-- verbatim.
-- Reference: CommonMark spec, section "HTML blocks" (behaviour only, no code
-- or text copied; see doc/references.md).
local container = require("doc_preview.markdown.container")

local M = {}

local RAW = { script = true, pre = true, style = true, textarea = true }

local BLOCK_NAMES = {}
for name in
  ([[address article aside base basefont blockquote body caption center col colgroup dd
  details dialog dir div dl dt fieldset figcaption figure footer form frame frameset
  h1 h2 h3 h4 h5 h6 head header hr html iframe legend li link main menu menuitem nav
  noframes ol optgroup option p param search section summary table tbody td tfoot th
  thead title tr track ul]]):gmatch("%S+")
do
  BLOCK_NAMES[name] = true
end

local function skip_space(s, i)
  return s:match("^[ \t\r\n]*()", i)
end

-- Attribute starting at i (after required whitespace); returns the index after
-- it, or nil when there is none.
local function attribute(s, i)
  local after = s:match("^[%a_:][%w_.:%-]*()", i)
  if not after then
    return nil
  end
  local eq = skip_space(s, after)
  if s:sub(eq, eq) ~= "=" then
    return after
  end
  local v = skip_space(s, eq + 1)
  local q = s:sub(v, v)
  if q == '"' or q == "'" then
    local close = s:find(q, v + 1, true)
    return close and close + 1
  end
  return s:match("^[^%s\"'=<>`]+()", v)
end

-- Closing tag at s[i] (`</`); returns the index after `>` and the lowercase
-- name, else nil.
local function closing_tag(s, i)
  local name, after = s:match("^([%a][%w%-]*)()", i + 2)
  if not name then
    return nil
  end
  local gt = skip_space(s, after)
  if s:sub(gt, gt) == ">" then
    return gt + 1, name:lower()
  end
  return nil
end

-- Index after the `>` ending an open tag whose name ends before pos, else nil.
local function open_tag_end(s, pos)
  while true do
    local nxt = skip_space(s, pos)
    local c = s:sub(nxt, nxt)
    if nxt > pos and c ~= "/" and c ~= ">" then
      pos = attribute(s, nxt)
      if not pos then
        return nil
      end
    else
      if c == "/" then
        nxt = nxt + 1
        c = s:sub(nxt, nxt)
      end
      if c == ">" then
        return nxt + 1
      end
      return nil
    end
  end
end

-- Complete open or closing tag at s[i] (`<`); returns the index after `>`
-- and the lowercase tag name, else nil. Shared with the inline matcher.
function M.tag_at(s, i)
  if s:sub(i, i + 1) == "</" then
    return closing_tag(s, i)
  end
  local name, pos = s:match("^<([%a][%w%-]*)()", i)
  if not name then
    return nil
  end
  local after = open_tag_end(s, pos)
  if not after then
    return nil
  end
  return after, name:lower()
end

-- Raw inline HTML at s[i] (`<`): tag, comment, processing instruction,
-- declaration or CDATA; returns the matched string, else nil.
function M.inline_match(s, i)
  local after = M.tag_at(s, i)
  if after then
    return s:sub(i, after - 1)
  end
  for _, f in ipairs({
    { "<!-->", "" },
    { "<!--->", "" },
    { "<!--", "-->" },
    { "<?", "?>" },
    { "<![CDATA[", "]]>" },
  }) do
    if s:sub(i, i + #f[1] - 1) == f[1] then
      if f[2] == "" then
        return f[1]
      end
      local _, e = s:find(f[2], i + #f[1], true)
      return e and s:sub(i, e)
    end
  end
  local e = s:match("^<!%a[^>]*>()", i)
  return e and s:sub(i, e - 1)
end

local function tag_rest_ok(rest)
  return rest == "" or rest:match("^[ \t>]") ~= nil
end

-- Condition 1-5 for a line starting with `<`, else nil.
local function start_1_to_5(s, lname, closing, rest)
  if lname and RAW[lname] and not closing and tag_rest_ok(rest) then
    return 1
  elseif s:sub(1, 4) == "<!--" then
    return 2
  elseif s:sub(1, 2) == "<?" then
    return 3
  elseif s:sub(1, 9) == "<![CDATA[" then
    return 5
  elseif s:match("^<!%a") then
    return 4
  end
  return nil
end

local function is_block_tag(lname, rest)
  if not (lname and BLOCK_NAMES[lname]) then
    return false
  end
  return tag_rest_ok(rest) or rest:sub(1, 2) == "/>"
end

local function is_lone_tag(s)
  local after, tag = M.tag_at(s, 1)
  return after ~= nil and not RAW[tag] and s:match("^[ \t]*$", after) ~= nil
end

-- Lowercased tag name, closing flag and text after the name for `s`.
local function tag_parts(s)
  local name = s:match("^</?(%a[%w%-]*)")
  if not name then
    return nil, false, nil
  end
  local closing = s:sub(2, 2) == "/"
  return name:lower(), closing, s:sub(#name + (closing and 3 or 2))
end

-- Start condition 1-7 for a line, else nil. Condition 7 never interrupts a
-- paragraph.
function M.block_start(line, para_open)
  local indent, at = container.expand_indent(line)
  if indent > 3 or line:sub(at, at) ~= "<" then
    return nil
  end
  local s = line:sub(at)
  local lname, closing, rest = tag_parts(s)
  local kind = start_1_to_5(s, lname, closing, rest)
  if kind then
    return kind
  end
  if is_block_tag(lname, rest) then
    return 6
  end
  if not para_open and is_lone_tag(s) then
    return 7
  end
  return nil
end

-- True when `line` holds the end marker of condition 1-5.
function M.block_end(line, kind)
  if kind == 1 then
    local l = line:lower()
    return l:find("</script>", 1, true)
      or l:find("</pre>", 1, true)
      or l:find("</style>", 1, true)
      or l:find("</textarea>", 1, true)
  elseif kind == 2 then
    return line:find("-->", 1, true) ~= nil
  elseif kind == 3 then
    return line:find("?>", 1, true) ~= nil
  elseif kind == 4 then
    return line:find(">", 1, true) ~= nil
  end
  return line:find("]]>", 1, true) ~= nil
end

-- Collects the block of condition `kind` opened at lines[k]; returns the
-- pending entry and the index of the first line after it.
function M.take_html(lines, linenos, k, kind)
  local body, j = {}, k
  while j <= #lines do
    if kind >= 6 and j > k and lines[j]:match("^%s*$") then
      break
    end
    body[#body + 1] = lines[j]
    j = j + 1
    if kind <= 5 and M.block_end(lines[j - 1], kind) then
      break
    end
  end
  local entry =
    { html = true, lines = body, start = linenos[k], last = linenos[j - 1], body = linenos[k] }
  return entry, j
end

return M
