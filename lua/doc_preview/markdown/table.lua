-- Markdown pipe tables (GFM extension): row splitting, delimiter row and
-- body collection. Pure line helpers; markdown/block drives detection (the
-- header is the last line of the open paragraph).
-- Reference: GFM spec, section "Tables (extension)" (behaviour only, no code
-- or text copied; see doc/references.md).
local container = require("doc_preview.markdown.container")

local M = {}

local function trim(s)
  return (s:gsub("^[ \t]+", ""):gsub("[ \t]+$", ""))
end

-- Consumes the char at s[i] into st; returns the next index.
local function split_step(s, i, st)
  local c = s:sub(i, i)
  st.trailing = false
  if c == "\\" and s:sub(i + 1, i + 1) == "|" then
    st.buf[#st.buf + 1] = "|"
    return i + 2
  elseif c == "|" then
    st.cells[#st.cells + 1] = trim(table.concat(st.buf))
    st.buf, st.trailing = {}, true
  else
    st.buf[#st.buf + 1] = c
  end
  return i + 1
end

-- Cell texts of a table row: outer pipes optional, `\|` is a literal pipe
-- (also inside code spans), cells trimmed.
function M.split_row(line)
  local s = trim(line)
  local st = { cells = {}, buf = {}, trailing = false }
  local i = s:sub(1, 1) == "|" and 2 or 1
  while i <= #s do
    i = split_step(s, i, st)
  end
  if not st.trailing then
    st.cells[#st.cells + 1] = trim(table.concat(st.buf))
  end
  if #st.cells == 1 and st.cells[1] == "" and not s:find("|", 1, true) then
    return {}
  end
  return st.cells
end

local function cell_align(cell)
  local left, right = cell:sub(1, 1) == ":", cell:sub(-1) == ":"
  if left and right then
    return "center"
  end
  return (left and "left") or (right and "right") or nil
end

-- Alignment list (entries may be nil, so also returns the column count) for a
-- delimiter row, else nil.
function M.delimiter(line)
  local indent = container.expand_indent(line)
  if indent > 3 or not line:find("|", 1, true) then
    return nil
  end
  local cells = M.split_row(line)
  if #cells == 0 then
    return nil
  end
  local align = {}
  for i, cell in ipairs(cells) do
    if not cell:match("^:?%-+:?$") then
      return nil
    end
    align[i] = cell_align(cell)
  end
  return align, #cells
end

local function fit(cells, n)
  local row = {}
  for i = 1, n do
    row[i] = cells[i] or ""
  end
  return row
end

-- Body rows from line k on (the line after the delimiter), up to a blank
-- line, a lazy line or a line for which starts_block is true. Returns rows
-- (n cell texts each, padded or truncated), index of the first line after the
-- table and the source line of the last row.
function M.take_rows(lines, lazy, k, n, starts_block)
  local rows = {}
  while k <= #lines do
    local line = lines[k]
    if line:match("^%s*$") or lazy[k] or starts_block(line) then
      break
    end
    rows[#rows + 1] = fit(M.split_row(line), n)
    k = k + 1
  end
  return rows, k
end

return M
