-- Display-width helpers: width, greedy word wrap, pad (doc/architecture.md 4.1).
-- Pure functions. Widths use nvim_strwidth, not strdisplaywidth: the latter
-- depends on the current window (a wide char at the last column counts extra).
local M = {}

---@param s string
---@return integer
function M.width(s)
  return vim.api.nvim_strwidth(s)
end

local CHAR = "[%z\1-\127\194-\244][\128-\191]*"

-- Split the word s[from, to) (0-based, end exclusive) into pieces of at most
-- `width` columns, cut at character boundaries: { {from, to, width}, ... }.
local function split_word(s, from, to, width)
  local pieces, start, w = {}, from, 0
  for pos, ch in s:sub(from + 1, to):gmatch("()(" .. CHAR .. ")") do
    local at, cw = from + pos - 1, M.width(ch)
    if w + cw > width and at > start then
      pieces[#pieces + 1] = { start, at, w }
      start, w = at, 0
    end
    w = w + cw
  end
  pieces[#pieces + 1] = { start, to, w }
  return pieces
end

-- Greedy layout of `s` (all whitespace is a break opportunity). Returns lines
-- of segments { from, to, col, text }: `from`/`to` are 0-based byte offsets in
-- the original text (`base` added), `col` the byte column in the output line.
local function layout(s, width, base)
  local lines, cur, cur_w, cur_len = {}, {}, 0, 0
  local function finish_line()
    lines[#lines + 1] = cur
    cur, cur_w, cur_len = {}, 0, 0
  end
  local function put(from, to, w)
    local gap = #cur > 0 and 1 or 0
    local seg = { from = base + from, to = base + to, col = cur_len + gap }
    seg.text = s:sub(from + 1, to)
    cur[#cur + 1] = seg
    cur_w, cur_len = cur_w + gap + w, cur_len + gap + (to - from)
  end
  for pos, word, stop in s:gmatch("()(%S+)()") do
    local from, to, w = pos - 1, stop - 1, M.width(word)
    if #cur > 0 and cur_w + 1 + w > width then
      finish_line()
    end
    if w <= width then
      put(from, to, w)
    else
      local pieces = split_word(s, from, to, width)
      for k, p in ipairs(pieces) do
        put(p[1], p[2], p[3])
        if k < #pieces then
          finish_line()
        end
      end
    end
  end
  if #cur > 0 then
    finish_line()
  end
  return lines
end

local function join(segs)
  local texts = {}
  for _, seg in ipairs(segs) do
    texts[#texts + 1] = seg.text
  end
  return table.concat(texts, " ")
end

---@param s string
---@param width integer  values below 1 count as 1
---@return string[]
function M.wrap(s, width)
  local lines = {}
  for _, segs in ipairs(layout(s, math.max(width, 1), 0)) do
    lines[#lines + 1] = join(segs)
  end
  return lines
end

-- Spans (output line numbers `line`) for the ranges that touch these segments.
local function add_spans(spans, line, segs, ranges)
  for _, r in ipairs(ranges) do
    local c1, c2
    for _, seg in ipairs(segs) do
      local a, b = math.max(r.from, seg.from), math.min(r.to, seg.to)
      if a < b then
        c1 = c1 or seg.col + a - seg.from
        c2 = seg.col + b - seg.from
      end
    end
    if c1 then
      spans[#spans + 1] = { line = line, col_start = c1, col_end = c2, hl_group = r.group }
    end
  end
end

-- Like wrap, but "\n" in `s` is a hard line break and `ranges`
-- ({ from, to, group }, 0-based byte offsets in `s`, end exclusive) come back
-- as spans on the wrapped lines (line 1-based, columns 0-based).
---@param s string
---@param width integer
---@param ranges table[]
---@return string[] lines
---@return table[] spans
function M.wrap_styled(s, width, ranges)
  local lines, spans, base = {}, {}, 0
  for chunk in (s .. "\n"):gmatch("([^\n]*)\n") do
    for _, segs in ipairs(layout(chunk, math.max(width, 1), base)) do
      lines[#lines + 1] = join(segs)
      add_spans(spans, #lines, segs, ranges)
    end
    base = base + #chunk + 1
  end
  return lines, spans
end

-- Expand tabs to spaces with tab stops every `tabstop` columns (default 4).
---@param s string
---@param tabstop? integer
---@return string
function M.expand_tabs(s, tabstop)
  tabstop = tabstop or 4
  local parts, col = {}, 0
  for ch in s:gmatch(CHAR) do
    if ch == "\t" then
      local n = tabstop - col % tabstop
      parts[#parts + 1] = (" "):rep(n)
      col = col + n
    else
      parts[#parts + 1] = ch
      col = col + M.width(ch)
    end
  end
  return table.concat(parts)
end

-- Cut `s` into rows of at most `width` columns at character boundaries,
-- keeping every space. Always at least one row; a char wider than `width`
-- gets a row of its own.
---@param s string
---@param width integer  values below 1 count as 1
---@return string[]
function M.hard_wrap(s, width)
  local rows = {}
  for _, p in ipairs(split_word(s, 0, #s, math.max(width, 1))) do
    rows[#rows + 1] = s:sub(p[1] + 1, p[2])
  end
  return rows
end

---@param s string
---@param width integer
---@param align? "left"|"right"|"center"  default "left"
---@return string
function M.pad(s, width, align)
  local gap = width - M.width(s)
  if gap <= 0 then
    return s
  end
  if align == "right" then
    return string.rep(" ", gap) .. s
  elseif align == "center" then
    local left = math.floor(gap / 2)
    return string.rep(" ", left) .. s .. string.rep(" ", gap - left)
  end
  return s .. string.rep(" ", gap)
end

return M
