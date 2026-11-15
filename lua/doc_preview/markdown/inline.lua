-- Markdown inline pass: code spans, backslash escapes, entities, hard and
-- soft breaks, emphasis, strong, GFM strikethrough, links, images and
-- autolinks, raw inline HTML. Text -> inline nodes.
-- Reference: CommonMark spec sections "Emphasis and strong emphasis", "Code
-- spans", "Backslash escapes", "Entity and numeric character references",
-- "Hard line breaks", "Soft line breaks", "Links", "Images", "Autolinks"; GFM
-- "Strikethrough (extension)".
-- Behaviour only; the delimiter-stack idea was studied in commonmark.js
-- (BSD-2-Clause) `inlines.js`, no code copied (doc/references.md).
-- Limits: punctuation and whitespace classes are ASCII (plus U+00A0); only
-- the named entities in markdown/entities.lua are decoded.
local model = require("doc_preview.document.model")
local footnote = require("doc_preview.markdown.footnote")
local html = require("doc_preview.markdown.html")
local link_syntax = require("doc_preview.markdown.link_syntax")
local unescape = require("doc_preview.markdown.unescape")

local M = {}

local CHAR = "[%z\1-\127\194-\244][\128-\191]*"

local function add_text(items, str)
  items[#items + 1] = model.text(str)
end

-- Flanking helpers: "" (start or end of text) counts as whitespace.
local function is_ws(c)
  return c == "" or c:match("^%s$") ~= nil or c == "\194\160"
end

local function is_punct(c)
  return c:match("^%p$") ~= nil
end

local function char_before(s, i)
  return s:sub(math.max(1, i - 4), i - 1):match(CHAR .. "$") or ""
end

local function char_after(s, i)
  return s:match("^" .. CHAR, i) or ""
end

-- Left and right flanking of a run between the characters `before`/`after`.
local function flanking(before, after)
  local bw, aw, bp, ap = is_ws(before), is_ws(after), is_punct(before), is_punct(after)
  local left = not aw and (not ap or bw or bp)
  local right = not bw and (not bp or aw or ap)
  return left, right, bp, ap
end

local function delimiter(s, i, j, ch)
  local left, right, bp, ap = flanking(char_before(s, i), char_after(s, j + 1))
  local open, close = left, right
  if ch == "_" then
    open = left and (not right or bp)
    close = right and (not left or ap)
  end
  local n = j - i + 1
  return { delim = true, char = ch, count = n, orig = n, can_open = open, can_close = close }
end

local function code_content(raw)
  local content = raw:gsub("\n", " ")
  if content:match("^ .* $") and content:match("[^ ]") then
    content = content:sub(2, -2)
  end
  return content
end

local handlers = {}
local process, finish

handlers["\\"] = function(s, i, items)
  local nxt = s:sub(i + 1, i + 1)
  if nxt == "\n" then
    items[#items + 1] = model.hardbreak()
    return i + 2
  elseif nxt:match("^%p$") then
    add_text(items, nxt)
    return i + 2
  end
  add_text(items, "\\")
  return i + 1
end

handlers["`"] = function(s, i, items)
  local n = #s:match("^`+", i)
  local from = i + n
  while true do
    local a, b = s:find("`+", from)
    if not a then
      add_text(items, ("`"):rep(n))
      return i + n
    elseif b - a + 1 == n then
      items[#items + 1] = model.code(code_content(s:sub(i + n, a - 1)))
      return b + 1
    end
    from = b + 1
  end
end

handlers["&"] = function(s, i, items)
  local body = s:match("^&([#%w]+);", i)
  local decoded = body and unescape.decode(body)
  if decoded then
    add_text(items, decoded)
    return i + #body + 2
  end
  add_text(items, "&")
  return i + 1
end

handlers["\n"] = function(_, i, items)
  local last, spaces = items[#items], 0
  if last and last.kind == "text" then
    spaces = #last.value:match(" *$")
    last.value = last.value:sub(1, #last.value - spaces)
  end
  items[#items + 1] = spaces >= 2 and model.hardbreak() or model.softbreak()
  return i + 1
end

-- Brackets: "[" and "![" are pushed as items, "]" resolves the latest one.
-- `at` is the index of the "[" in the source.
local function bracket(items, i, image)
  local width = image and 2 or 1
  items[#items + 1] = { bracket = true, image = image, active = true, at = i + width - 1 }
  return i + width
end

handlers["["] = function(_, i, items)
  return bracket(items, i, false)
end

handlers["!"] = function(s, i, items)
  if s:sub(i + 1, i + 1) == "[" then
    return bracket(items, i, true)
  end
  add_text(items, "!")
  return i + 1
end

handlers["<"] = function(s, i, items)
  local target, shown, stop = link_syntax.autolink(s, i)
  if not target then
    local raw = html.inline_match(s, i)
    if raw then
      items[#items + 1] = model.html_inline(raw)
      return i + #raw
    end
    add_text(items, "<")
    return i + 1
  end
  items[#items + 1] = model.link(target, nil, { model.text(shown) })
  return stop
end

local function last_bracket(items)
  for o = #items, 1, -1 do
    if items[o].bracket then
      return o
    end
  end
end

-- Full `[text][label]` (an undefined label is final), else collapsed
-- `[text][]` or shortcut `[text]`, whose label is the link text itself.
local function reference(s, i, opener, refs)
  local full, after = link_syntax.label(s, i + 1)
  if full then
    local def = refs[link_syntax.normalize(full)]
    return def and def.target, def and def.title, after
  end
  local own, stop = link_syntax.label(s, opener.at)
  if not own or stop ~= i + 1 then
    return nil
  end
  local def = refs[link_syntax.normalize(own)]
  return def and def.target, def and def.title, s:sub(i + 1, i + 2) == "[]" and i + 3 or i + 1
end

-- Target, title and index after the link whose text ends at the "]" at `i`.
local function resolve(s, i, opener, refs)
  if s:sub(i + 1, i + 1) == "(" then
    local target, title, stop = link_syntax.inline_tail(s, i + 1)
    if target then
      return target, title, stop
    end
  end
  return reference(s, i, opener, refs)
end

-- Plain text of an image description.
local function plain(inlines)
  local parts = {}
  for _, n in ipairs(inlines) do
    if n.kind == "softbreak" or n.kind == "hardbreak" then
      parts[#parts + 1] = " "
    else
      parts[#parts + 1] = n.value
        or n.alt
        or (n.label and "[^" .. n.label .. "]")
        or plain(n.inlines)
    end
  end
  return table.concat(parts)
end

-- A link makes every earlier "[" inactive: links do not nest.
local function deactivate(items, o)
  for k = 1, o - 1 do
    if items[k].bracket and not items[k].image then
      items[k].active = false
    end
  end
end

-- Removes and returns the items after index o.
local function take_after(items, o)
  local taken = {}
  for _ = o + 1, #items do
    taken[#taken + 1] = table.remove(items, o + 1)
  end
  return taken
end

-- Closes the link or image opened at items[o] around the inner items.
local function close_link(items, o, target, title)
  local opener = items[o]
  local inner = take_after(items, o)
  process(inner)
  inner = finish(inner)
  if opener.image then
    items[o] = model.image(target, title, plain(inner))
  else
    items[o] = model.link(target, title, inner)
    deactivate(items, o)
  end
end

handlers["]"] = function(s, i, items, refs)
  local o = last_bracket(items)
  if not o then
    add_text(items, "]")
    return i + 1
  end
  local opener = items[o]
  local fn = not opener.image and footnote.ref_label(s, opener.at, i, refs)
  if fn then
    take_after(items, o)
    items[o] = model.footnote_ref(fn)
    return i + 1
  end
  local target, title, stop
  if opener.active then
    target, title, stop = resolve(s, i, opener, refs)
  end
  if not target then
    items[o] = model.text(opener.image and "![" or "[")
    add_text(items, "]")
    return i + 1
  end
  close_link(items, o, target, title)
  return stop
end

local function run(s, i, items)
  local ch = s:sub(i, i)
  local _, j = s:find("^[" .. ch .. "]+", i)
  if ch == "~" and j - i + 1 > 2 then
    add_text(items, s:sub(i, j))
  else
    items[#items + 1] = delimiter(s, i, j, ch)
  end
  return j + 1
end
handlers["*"], handlers["_"], handlers["~"] = run, run, run

local function tokenize(s, refs)
  local items, i = {}, 1
  while i <= #s do
    local handler = handlers[s:sub(i, i)]
    if handler then
      i = handler(s, i, items, refs)
    else
      local chunk = s:match("^[^\\`*_~&\n<![%]]+", i)
      add_text(items, chunk)
      i = i + #chunk
    end
  end
  return items
end

-- Unmatched delimiters become text; adjacent text merges.
local function literal(item)
  if item.delim then
    return model.text(item.char:rep(item.count))
  elseif item.bracket then
    return model.text(item.image and "![" or "[")
  end
  return item
end

function finish(items)
  local res = {}
  for _, item in ipairs(items) do
    item = literal(item)
    local last = res[#res]
    if item.kind == "text" and last and last.kind == "text" then
      last.value = last.value .. item.value
    elseif item.kind ~= "text" or item.value ~= "" then
      res[#res + 1] = item
    end
  end
  return res
end

local function matches(opener, closer)
  if not (opener.delim and opener.can_open and opener.char == closer.char) then
    return false
  elseif closer.char == "~" then
    return opener.count == closer.count
  end
  local sum_odd = (opener.orig + closer.orig) % 3 == 0
  local both_triple = opener.orig % 3 == 0 and closer.orig % 3 == 0
  if (opener.can_close or closer.can_open) and sum_odd and not both_triple then
    return false
  end
  return true
end

local function find_opener(items, c)
  for o = c - 1, 1, -1 do
    if matches(items[o], items[c]) then
      return o
    end
    if items[c].char == "~" and items[o].delim and items[o].can_open and items[o].char == "~" then
      return nil -- cmark-gfm: the nearest `~` opener decides, a length mismatch ends the search
    end
  end
end

local function make_node(char, use, inner)
  if char == "~" then
    return model.strike(inner)
  end
  return (use == 2 and model.strong or model.emph)(inner)
end

-- Wrap items between opener `o` and closer `c` in one node. Returns the
-- index at which scanning continues.
local function wrap(items, o, c)
  local opener, closer = items[o], items[c]
  local use = (opener.count >= 2 and closer.count >= 2) and 2 or 1
  local inner = {}
  for _ = o + 1, c - 1 do
    inner[#inner + 1] = table.remove(items, o + 1)
  end
  table.insert(items, o + 1, make_node(opener.char, use, finish(inner)))
  opener.count, closer.count = opener.count - use, closer.count - use
  local next_i = o + 2
  if closer.count == 0 then
    table.remove(items, next_i)
  end
  if opener.count == 0 then
    table.remove(items, o)
    next_i = next_i - 1
  end
  return next_i
end

function process(items)
  local i = 1
  while i <= #items do
    local o = items[i].delim and items[i].can_close and find_opener(items, i)
    i = o and wrap(items, o, i) or i + 1
  end
end

---@param s string  paragraph or heading text, lines joined with "\n"
---@param refs? table  link reference definitions { key = { target, title } }
---@return table[] inline nodes
function M.parse(s, refs)
  s = s:gsub("\n[ \t]+", "\n")
  s = s:match("^[ \t]*(.-)[ \t]*$")
  local items = tokenize(s, refs or {})
  process(items)
  return finish(items)
end

return M
