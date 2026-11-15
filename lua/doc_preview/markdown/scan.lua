-- Markdown line-to-block scanner. linenos[k] is the source line of lines[k];
-- lazy[k] marks quote lazy continuation lines (never setext underlines).
-- Each line is probed once, then the first matching rule in RULES consumes
-- one or more lines and returns the index of the last line it consumed.
-- Reference: CommonMark spec (see markdown/block and doc/references.md).
local container = require("doc_preview.markdown.container")
local code = require("doc_preview.markdown.code")
local html = require("doc_preview.markdown.html")
local gfm_table = require("doc_preview.markdown.table")
local footnote = require("doc_preview.markdown.footnote")
local leaf = require("doc_preview.markdown.leaf")
local job = require("doc_preview.core.job")

local M = {}

local scan

-- True when a table body row line starts another block.
local function starts_block(line)
  return leaf.atx(line)
    or leaf.thematic(line)
    or code.fence_open(line)
    or html.block_start(line, true)
    or container.quote_marker(line)
    or container.item_marker(line, true)
end

-- Delimiter row alignment and column count when line turns the last chunk
-- line into a table header, else nil.
local function table_align(line, chunk, lazy_k)
  if lazy_k or #chunk == 0 then
    return nil
  end
  local align, n = gfm_table.delimiter(line)
  if
    align
    and not container.item_marker(line, true)
    and #gfm_table.split_row(chunk[#chunk]) == n
  then
    return align, n
  end
end

local function push(st, entry)
  st.pending[#st.pending + 1] = entry
end

local function add(st, level, text, first, last)
  push(st, { level = level, text = text, start = st.linenos[first], last = st.linenos[last] })
end

local function flush(st, last)
  if st.start then
    add(st, nil, table.concat(st.chunk, "\n"), st.start, last)
  end
  st.chunk, st.start = {}, nil
end

-- Everything the rules need to know about line k, computed once.
local function probe(st, k)
  local line, lazy = st.lines[k], st.lazy[k]
  local f = { line = line }
  f.level, f.content = leaf.atx(line)
  if st.start then
    f.align, f.ncols = table_align(line, st.chunk, lazy)
    f.underline = not lazy and leaf.setext(line)
  end
  f.rest = container.quote_marker(line)
  if not lazy then
    f.fence = code.fence_open(line)
    f.html_kind = html.block_start(line, st.start ~= nil)
    f.fn_label, f.fn_rest = footnote.start(line)
    f.indented = not st.start and code.is_indented(line)
  end
  return f
end

local function run_blank(st, k)
  flush(st, k - 1)
  return k
end

local function run_indented(st, k)
  local c, next_k = code.take_indented(st.lines, st.linenos, k)
  push(st, c)
  return next_k - 1
end

local function run_fence(st, k, f)
  flush(st, k - 1)
  local c, next_k = code.take_fence(st.lines, st.linenos, k, f.fence)
  push(st, c)
  return next_k - 1
end

local function run_footnote(st, k, f)
  flush(st, k - 1)
  local d, next_k = footnote.take(st.lines, st.linenos, st.lazy, k, f.fn_label, f.fn_rest, scan)
  push(st, d)
  st.open = d.open
  return next_k - 1
end

local function run_html(st, k, f)
  flush(st, k - 1)
  local h, next_k = html.take_html(st.lines, st.linenos, k, f.html_kind)
  push(st, h)
  return next_k - 1
end

local function run_table(st, k, f)
  local header = st.chunk[#st.chunk]
  st.chunk[#st.chunk] = nil
  if #st.chunk > 0 then
    flush(st, k - 2)
  end
  st.chunk, st.start = {}, nil
  local rows, next_k = gfm_table.take_rows(st.lines, st.lazy, k + 1, f.ncols, starts_block)
  push(st, {
    table = true,
    align = f.align,
    header = gfm_table.split_row(header),
    rows = rows,
    start = st.linenos[k - 1],
    last = st.linenos[next_k - 1],
  })
  return next_k - 1
end

local function run_heading(st, k, f)
  flush(st, k - 1)
  add(st, f.level, f.content, k, k)
  return k
end

local function run_underline(st, k, f)
  add(st, f.underline, table.concat(st.chunk, "\n"), st.start, k)
  st.chunk, st.start = {}, nil
  return k
end

local function run_rule(st, k)
  flush(st, k - 1)
  push(st, { rule = true, text = "", start = st.linenos[k], last = st.linenos[k] })
  return k
end

local function run_quote(st, k, f)
  flush(st, k - 1)
  local q, next_k = container.take_quote(st.lines, st.linenos, k, f.rest)
  push(st, q)
  st.open = q.open
  return next_k - 1
end

local function run_list(st, k, f)
  flush(st, k - 1)
  local marker = container.item_marker(f.line, false)
  local l, next_k = container.take_list(st.lines, st.linenos, st.lazy, k, marker)
  push(st, l)
  st.open = l.open
  return next_k - 1
end

local function run_text(st, k, f)
  st.start = st.start or k
  st.chunk[#st.chunk + 1] = leaf.clean(f.line)
  return k
end

local function is_blank(_, _, f)
  return f.line:match("^%s*$")
end

local function is_rule(_, _, f)
  return leaf.thematic(f.line)
end

local function is_item(st, _, f)
  return container.item_marker(f.line, st.start ~= nil)
end

local function always()
  return true
end

local function field(name)
  return function(_, _, f)
    return f[name]
  end
end

-- Order matters: the first matching rule wins.
local RULES = {
  { is_blank, run_blank },
  { field("indented"), run_indented },
  { field("fence"), run_fence },
  { field("fn_label"), run_footnote },
  { field("html_kind"), run_html },
  { field("align"), run_table },
  { field("level"), run_heading },
  { field("underline"), run_underline },
  { is_rule, run_rule },
  { field("rest"), run_quote },
  { is_item, run_list },
  { always, run_text },
}

local function step(st, k)
  local f = probe(st, k)
  st.open = false
  for _, rule in ipairs(RULES) do
    if rule[1](st, k, f) then
      return rule[2](st, k, f)
    end
  end
end

-- Returns pending entries and whether a paragraph or container is still open
-- after the last line (never after a code or HTML block: not lazily
-- continued).
function scan(lines, linenos, lazy)
  local st = {
    lines = lines,
    linenos = linenos,
    lazy = lazy,
    pending = {},
    chunk = {},
    start = nil,
    open = false,
  }
  local k = 1
  while k <= #lines do
    job.yield_point()
    k = step(st, k) + 1
  end
  local open = st.start ~= nil or st.open
  flush(st, #lines)
  return st.pending, open
end

M.scan = scan

return M
