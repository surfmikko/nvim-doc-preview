-- Markdown container blocks: block quotes and (single-level so far) list
-- items. Both share one idea: collect the container's source lines, strip the
-- container prefix, and hand the inner lines to the block scanner with a map
-- back to source lines. `scan`, `atx`, `thematic`, `fence_open` and
-- `html_start` live in markdown/block, code and html and are injected once
-- through setup() to avoid a require cycle.
-- Reference: CommonMark spec, sections "Block quotes", "List items", "Lists",
-- "Tabs" (behaviour only, no code or text copied; see doc/references.md).
local M = {}

local scan, atx, thematic, fence_open, html_start

function M.setup(scan_fn, atx_fn, thematic_fn, fence_open_fn, html_start_fn)
  scan, atx, thematic, fence_open, html_start =
    scan_fn, atx_fn, thematic_fn, fence_open_fn, html_start_fn
end

-- An unindented line starting an HTML block of conditions 1-6 ends a lazy
-- continuation (condition 7 cannot interrupt a paragraph).
local function interrupts(line)
  return html_start(line, true) ~= nil
end

-- Indent width in columns (tab stop 4) and the byte index of the first
-- non-blank character.
function M.expand_indent(line)
  local col, i = 0, 1
  while true do
    local c = line:sub(i, i)
    if c == " " then
      col = col + 1
    elseif c == "\t" then
      col = col + 4 - col % 4
    else
      return col, i
    end
    i = i + 1
  end
end

local expand_indent = M.expand_indent

local function is_blank(line)
  return line:match("^%s*$") ~= nil
end

-- Removes n columns of leading whitespace; a tab cut in the middle leaves
-- the remaining columns as spaces.
local function strip_columns(line, n)
  local col, i = 0, 1
  while col < n do
    local c = line:sub(i, i)
    if c == " " then
      col = col + 1
    elseif c == "\t" then
      col = col + 4 - col % 4
    else
      break
    end
    i = i + 1
  end
  return string.rep(" ", math.max(col - n, 0)) .. line:sub(i)
end

M.strip_columns = strip_columns

-- Returns the line content after a block quote marker (0-3 columns of indent,
-- `>`, one optional space; a tab counts as that space), else nil.
function M.quote_marker(line)
  local indent, at = expand_indent(line)
  if indent > 3 or line:sub(at, at) ~= ">" then
    return nil
  end
  local after = line:sub(at + 1, at + 1)
  if after == " " then
    return line:sub(at + 2)
  elseif after == "\t" then
    local col = indent + 1
    return string.rep(" ", 3 - col % 4) .. line:sub(at + 2)
  end
  return line:sub(at + 1)
end

local quote_marker = M.quote_marker

-- Marker fields and width for a bullet or an ordered marker at the start of
-- text, else nil.
local function marker_head(text)
  local digits, d = text:match("^(%d+)([.)])")
  if digits then
    if #digits > 9 then
      return nil
    end
    return { ordered = true, number = tonumber(digits), delim = d }, #digits + 1
  end
  if text:match("^[-+*]") then
    return { ordered = false, delim = text:sub(1, 1) }, 1
  end
  return nil
end

local function marker_end(after)
  return after == "" or after == " " or after == "\t"
end

-- Column and byte index after the blanks starting at byte i (column c).
local function skip_blanks(line, i, c)
  while line:sub(i, i) == " " or line:sub(i, i) == "\t" do
    c = line:sub(i, i) == " " and c + 1 or c + 4 - c % 4
    i = i + 1
  end
  return c, i
end

-- Content column and first content line (col: after the marker, c: after the
-- blanks, i: byte index of the content).
local function set_content(m, line, i, col, c)
  local spaces = c - col
  m.content_col = (m.empty or spaces >= 5) and col + 1 or col + spaces
  m.rest = m.empty and "" or string.rep(" ", c - m.content_col) .. line:sub(i)
end

local function cannot_interrupt(m, para_open)
  return para_open and (m.empty or (m.ordered and m.number ~= 1))
end

-- Returns a list item start: { ordered, number, delim, content_col, empty,
-- rest } (rest is the first line of content, stripped), else nil. With
-- para_open the item may not interrupt a paragraph if it is empty or an
-- ordered item not numbered 1.
function M.item_marker(line, para_open)
  local indent, at = expand_indent(line)
  if indent > 3 then
    return nil
  end
  local m, width = marker_head(line:sub(at))
  if not m or not marker_end(line:sub(at + width, at + width)) then
    return nil
  end
  local col = indent + width
  local c, i = skip_blanks(line, at + width, col)
  m.empty = i > #line
  if cannot_interrupt(m, para_open) then
    return nil
  end
  set_content(m, line, i, col, c)
  return m
end

local item_marker = M.item_marker

-- Whether a paragraph or container is open after the last inner line. memo
-- caches the answer between calls; callers clear memo.open when they append a
-- non-lazy line. An accepted lazy line keeps the paragraph open, so it sets it.
local function is_open(inner, inner_nos, inner_lazy, memo)
  if memo.open == nil then
    local _, open = scan(inner, inner_nos, inner_lazy)
    memo.open = open
  end
  return memo.open
end

-- Collects the quote starting at line k (first_rest is its stripped content).
-- Returns the quote entry and the index of the first line after it.
function M.take_quote(lines, linenos, k, first_rest)
  local inner, inner_nos, inner_lazy = { first_rest }, { linenos[k] }, {}
  local memo = {}
  local j = k + 1
  while j <= #lines do
    local line = lines[j]
    local rest = quote_marker(line)
    if rest then
      inner[#inner + 1] = rest
      memo.open = nil
    elseif
      is_blank(line)
      or atx(line)
      or thematic(line)
      or fence_open(line)
      or interrupts(line)
      or item_marker(line, false)
    then
      break
    else
      if not is_open(inner, inner_nos, inner_lazy, memo) then
        break
      end
      inner[#inner + 1] = line
      inner_lazy[#inner] = true
      memo.open = true
    end
    inner_nos[#inner] = linenos[j]
    j = j + 1
  end
  local children, open = scan(inner, inner_nos, inner_lazy)
  return {
    quote = true,
    children = children,
    open = open,
    start = linenos[k],
    last = linenos[j - 1],
  },
    j
end

function M.next_nonblank(lines, j)
  while j <= #lines and is_blank(lines[j]) do
    j = j + 1
  end
  if j <= #lines then
    return j
  end
end

local function same_kind(a, b)
  return a.ordered == b.ordered and a.delim == b.delim
end

-- True when a less indented line ends the item: it starts another block (any
-- item start does, the interrupt rule only applies inside one container), or
-- is not a paragraph continuation.
function M.ends_item(line, inner, inner_nos, inner_lazy, memo)
  if thematic(line) or atx(line) or fence_open(line) or interrupts(line) or quote_marker(line) then
    return true
  end
  if item_marker(line, false) then
    return true
  end
  return not is_open(inner, inner_nos, inner_lazy, memo or {})
end

-- Collects one item whose marker `m` is on line j0. Returns the item entry and
-- the index of the first line after it.
local function take_item(lines, linenos, lazy, j0, m)
  local col = m.content_col
  local inner, inner_nos, inner_lazy = { m.rest }, { linenos[j0] }, {}
  local memo = {}
  local j = j0 + 1
  while j <= #lines do
    local line = lines[j]
    if is_blank(line) then
      local n = M.next_nonblank(lines, j)
      if (#inner == 1 and m.empty) or not n or expand_indent(lines[n]) < col then
        break
      end
      for b = j, n - 1 do
        inner[#inner + 1] = ""
        inner_nos[#inner] = linenos[b]
      end
      memo.open = nil
      j = n
    else
      if expand_indent(line) >= col then
        inner[#inner + 1] = strip_columns(line, col)
        inner_lazy[#inner] = lazy[j]
        memo.open = nil
      elseif M.ends_item(line, inner, inner_nos, inner_lazy, memo) then
        break
      else
        inner[#inner + 1] = line
        inner_lazy[#inner] = true
        memo.open = true
      end
      inner_nos[#inner] = linenos[j]
      j = j + 1
    end
  end
  local children, open = scan(inner, inner_nos, inner_lazy)
  return { children = children, open = open, start = linenos[j0], last = inner_nos[#inner] }, j
end

-- A list is loose when a blank line separates two adjacent items or two
-- direct children of one item. Source line gaps are exactly blank lines: item
-- ends never include trailing blanks.
local function is_tight(items)
  for i, it in ipairs(items) do
    if items[i + 1] and items[i + 1].start - it.last > 1 then
      return false
    end
    for c = 2, #it.children do
      if it.children[c].start - it.children[c - 1].last > 1 then
        return false
      end
    end
  end
  return true
end

-- Collects the list whose first item marker `first` is on line k. Returns the
-- list entry and the index of the first line after it.
function M.take_list(lines, linenos, lazy, k, first)
  local items, m, j = {}, first, k
  while true do
    local item
    item, j = take_item(lines, linenos, lazy, j, m)
    items[#items + 1] = item
    local n = M.next_nonblank(lines, j)
    local nm = n and not thematic(lines[n]) and item_marker(lines[n], false)
    if not (nm and same_kind(nm, first)) then
      break
    end
    m, j = nm, n
  end
  local last = items[#items]
  return {
    list = true,
    ordered = first.ordered,
    number = first.number or 1,
    delim = first.delim,
    items = items,
    tight = is_tight(items),
    open = last.open,
    start = linenos[k],
    last = last.last,
  },
    j
end

return M
