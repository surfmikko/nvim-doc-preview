-- document.model -> Output (doc/architecture.md 4.3). Run it inside a
-- core/job so yield_point() can slice the work.
local box = require("doc_preview.core.box")
local errbox = require("doc_preview.core.errbox")
local footnote_render = require("doc_preview.document.footnote_render")
local job = require("doc_preview.core.job")
local linklist = require("doc_preview.document.linklist")
local mermaid = require("doc_preview.mermaid")
local out = require("doc_preview.core.out")
local table_render = require("doc_preview.document.table_render")
local text = require("doc_preview.core.text")

local DEFAULT_WIDTH = 80

local M = {}

-- Test only: called with each top-level node before it is rendered. A test
-- simulates a slow block by burning time and calling job.yield_point() here.
M.test_hook = nil

local GROUPS = {
  emph = "DocPreviewEmph",
  strong = "DocPreviewStrong",
  strike = "DocPreviewStrike",
  code = "DocPreviewCode",
  link = "DocPreviewLink",
  html_inline = "DocPreviewHtml",
}

local function push(st, piece, group)
  local from = st.len
  st.parts[#st.parts + 1] = piece
  st.len = st.len + #piece
  if group and st.len > from then
    st.ranges[#st.ranges + 1] = { from = from, to = st.len, group = group }
  end
end

-- Text of a leaf node: soft break a space, hard break "\n", newlines inside
-- text values count as spaces. Nil for container nodes and images.
local function leaf_text(node)
  if node.kind == "softbreak" then
    return " "
  elseif node.kind == "hardbreak" then
    return "\n"
  end
  local value = node.value
  return value and (value:gsub("\n", " "))
end

local IMAGE_GROUP = "DocPreviewImage"

local function placeholder(alt)
  local text_alt = alt:gsub("\n", " ")
  return text_alt == "" and "[image]" or "[image: " .. text_alt .. "]"
end

-- Append the plain text of `inlines` to st.parts and the styled byte ranges
-- (0-based, end exclusive) to st.ranges. A link is its text plus a "[n]" marker.
local function flatten(inlines, st)
  for _, node in ipairs(inlines) do
    local from, piece = st.len, leaf_text(node)
    if node.kind == "footnote_ref" then
      push(st, footnote_render.marker(st.ctx, node.label, st.line))
    elseif node.kind == "image" then
      push(st, placeholder(node.alt), IMAGE_GROUP)
    elseif piece then
      push(st, piece)
    else
      flatten(node.inlines or {}, st)
    end
    if GROUPS[node.kind] and st.len > from then
      st.ranges[#st.ranges + 1] = { from = from, to = st.len, group = GROUPS[node.kind] }
    end
    if node.kind == "link" then
      local n = linklist.number(st.links, node.target, st.line)
      push(st, "[" .. n .. "]", "DocPreviewLinkMark")
    end
  end
end

local function paragraph(node, ctx)
  local frag = out.new()
  local st =
    { parts = {}, ranges = {}, len = 0, links = ctx.links, line = node.src_start, ctx = ctx }
  flatten(node.inlines, st)
  local lines, spans =
    text.wrap_styled(table.concat(st.parts), ctx.width or DEFAULT_WIDTH, st.ranges)
  if #lines == 0 then
    lines = { "" }
  end
  for _, line in ipairs(lines) do
    frag:add_line(line)
  end
  for _, s in ipairs(spans) do
    frag:add_span(s.line, s.col_start, s.col_end, s.hl_group)
  end
  frag:add_map(1, #frag.lines, node.src_start, node.src_end)
  return frag
end

local function image_block(node, ctx)
  local frag = out.new()
  local s = placeholder(node.alt)
  local lines, spans =
    text.wrap_styled(s, ctx.width or DEFAULT_WIDTH, { { from = 0, to = #s, group = IMAGE_GROUP } })
  for _, line in ipairs(lines) do
    frag:add_line(line)
  end
  for _, sp in ipairs(spans) do
    frag:add_span(sp.line, sp.col_start, sp.col_end, sp.hl_group)
  end
  frag:add_map(1, #frag.lines, node.src_start, node.src_end)
  return frag
end

local function heading(node, ctx)
  local frag = paragraph(node, ctx)
  local group = "DocPreviewH" .. node.level
  for i, line in ipairs(frag.lines) do
    if line ~= "" then
      frag:add_span(i, 0, #line, group)
    end
  end
  return frag
end

-- Verbatim rows, tabs expanded, hard-wrapped at the width; every row of
-- lines[i] maps to source line src_body + i - 1.
local function verbatim_block(node, ctx, group)
  local frag = out.new()
  local width = ctx.width or DEFAULT_WIDTH
  for i, line in ipairs(node.lines) do
    local first = #frag.lines + 1
    for _, row in ipairs(text.hard_wrap(text.expand_tabs(line), width)) do
      local n = frag:add_line(row)
      if row ~= "" then
        frag:add_span(n, 0, #row, group)
      end
    end
    local src = node.src_body + i - 1
    frag:add_map(first, #frag.lines, src, src)
  end
  if #frag.lines == 0 then
    frag:add_line("")
    frag:add_map(1, 1, node.src_start, node.src_end)
  end
  return frag
end

-- lang -> { render = fn(lines, ctx) -> Output, flag = ctx.engines key }
local engines = {
  mermaid = { render = mermaid.render, flag = "mermaid" },
}

-- Exposed so tests can swap an engine for a failing one.
M.engines = engines

local function engine_for(node, ctx)
  local engine = node.lang and engines[node.lang]
  if engine and (ctx.engines or {})[engine.flag] ~= false then
    return engine
  end
end

-- pcall plus Output validation; any failure becomes an errbox (4.5).
local function safe(engine, node, ctx)
  local width = ctx.width or DEFAULT_WIDTH
  local sub = { width = width, charset = ctx.charset }
  local ok, result = pcall(engine.render, node.lines, sub)
  if not ok or not out.valid(result, width) then
    local msg = ok and "invalid output" or tostring(result)
    return errbox.render(node.lines, sub, node.lang .. ": " .. msg)
  end
  return result
end

-- Engine blocks are atomic: one map entry over the whole block, fences included.
local function engine_block(engine, node, ctx)
  local frag = safe(engine, node, ctx)
  frag.map = {}
  frag:add_map(1, math.max(#frag.lines, 1), node.src_start, node.src_end)
  return frag
end

local function code_block(node, ctx)
  local engine = engine_for(node, ctx)
  if engine then
    return engine_block(engine, node, ctx)
  end
  return verbatim_block(node, ctx, "DocPreviewCode")
end

local function html_block(node, ctx)
  return verbatim_block(node, ctx, "DocPreviewHtml")
end

local function thematic_break(node, ctx)
  local frag = out.new()
  frag:add_line(box.rule_glyph(ctx.charset):rep(ctx.width or DEFAULT_WIDTH))
  frag:add_map(1, 1, node.src_start, node.src_end)
  return frag
end

-- Cell inlines as text and styled ranges, links numbered like paragraphs.
local function cell_text(ctx, inlines, line)
  local st = { parts = {}, ranges = {}, len = 0, links = ctx.links, line = line, ctx = ctx }
  flatten(inlines, st)
  return table.concat(st.parts), st.ranges
end

local function table_block(node, ctx)
  return table_render.render(node, ctx, function(inlines, line)
    return cell_text(ctx, inlines, line)
  end, ctx.width or DEFAULT_WIDTH)
end

local function unsupported(node)
  local frag = out.new()
  frag:add_line("[unsupported: " .. tostring(node.kind) .. "]")
  frag:add_map(1, 1, node.src_start or 1, node.src_end or 1)
  return frag
end

local render_blocks

local function blockquote(node, ctx)
  local prefix = box.quote_prefix(ctx.charset)
  local avail = ctx.width or DEFAULT_WIDTH
  local width = avail - text.width(prefix)
  if width < 1 then
    -- No room for the prefix plus one content column: drop this level's
    -- prefix so no line exceeds the width.
    prefix, width = "", avail
  end
  local inner = vim.tbl_extend("force", ctx, { width = width })
  local frag = render_blocks(node.children, inner)
  if #frag.lines == 0 then
    frag:add_line("")
    frag:add_map(1, 1, node.src_start, node.src_end)
  end
  return out.prefix(frag, prefix, "DocPreviewQuote")
end

local function bullet_glyph(ctx)
  return box.bullet(ctx.charset, ctx.list_depth or 0)
end

-- Marker text of item `index` (1-based) in `list`; numbers right-aligned.
local function item_marker(list, item, index, ctx)
  local marker
  if list.ordered then
    local widest = #tostring(list.start + #list.children - 1)
    marker = string.format("%" .. widest .. "d. ", list.start + index - 1)
  end
  if item.checked ~= nil then
    return (marker or "") .. (item.checked and "[x] " or "[ ] ")
  end
  return marker or (bullet_glyph(ctx) .. " ")
end

-- Marker on the first line, blank indent of the same width on the rest
-- (blank lines stay empty); spans and map entries are kept.
local function hang_prefix(frag, i, marker, indent)
  if i == 1 then
    return marker
  end
  return frag.lines[i] ~= "" and indent or ""
end

local function hang_shift(frag, line_no, marker, indent)
  if line_no == 1 then
    return #marker
  end
  return frag.lines[line_no] ~= "" and #indent or 0
end

local function hang(frag, marker)
  local result = out.new()
  local indent = (" "):rep(text.width(marker))
  for i, line in ipairs(frag.lines) do
    result:add_line(hang_prefix(frag, i, marker, indent) .. line)
    if i == 1 then
      result:add_span(1, 0, #marker, "DocPreviewListMarker")
    end
  end
  for _, s in ipairs(frag.spans) do
    local shift = hang_shift(frag, s.line, marker, indent)
    result:add_span(s.line, s.col_start + shift, s.col_end + shift, s.hl_group)
  end
  for _, m in ipairs(frag.map) do
    result:add_map(m.out_start, m.out_end, m.src_start, m.src_end)
  end
  return result
end

local function list_item(node, marker, tight, ctx)
  local width = math.max(1, (ctx.width or DEFAULT_WIDTH) - text.width(marker))
  local inner =
    vim.tbl_extend("force", ctx, { width = width, list_depth = (ctx.list_depth or 0) + 1 })
  local frag = render_blocks(node.children, inner, tight)
  if #frag.lines == 0 then
    frag:add_line("")
    frag:add_map(1, 1, node.src_start, node.src_start)
  end
  return hang(frag, marker)
end

local function list(node, ctx)
  local result = out.new()
  for i, item in ipairs(node.children) do
    job.yield_point()
    if i > 1 and not node.tight then
      result:add_line("")
    end
    result:append(list_item(item, item_marker(node, item, i, ctx), node.tight, ctx))
  end
  return result
end

local handlers = {
  list = list,
  paragraph = paragraph,
  image = image_block,
  heading = heading,
  thematic_break = thematic_break,
  code_block = code_block,
  html_block = html_block,
  blockquote = blockquote,
  table = table_block,
}

-- Blocks separated by a blank line; shared by the document and containers.
-- `tight` (list items): no blank line between a paragraph and a nested list.
function render_blocks(children, ctx, tight)
  local result = out.new()
  children = footnote_render.without_defs(children)
  for i, node in ipairs(children) do
    job.yield_point()
    if M.test_hook then
      M.test_hook(node, ctx)
    end
    local joined = tight and i > 1 and children[i - 1].kind == "paragraph" and node.kind == "list"
    if i > 1 and not joined then
      result:add_line("")
    end
    result:append((handlers[node.kind] or unsupported)(node, ctx))
  end
  return result
end

---@param doc table document node
---@param ctx table
---@return doc_preview.Output
function M.render(doc, ctx)
  ctx.links = linklist.new()
  footnote_render.setup(ctx, doc)
  local result = render_blocks(doc.children, ctx)
  local notes = footnote_render.section(ctx, function(def, marker, c)
    return list_item(def, marker, false, c)
  end)
  if notes then
    result:add_line("")
    result:append(notes)
  end
  local section = linklist.section(ctx.links, ctx.width or DEFAULT_WIDTH)
  if section then
    result:add_line("")
    result:append(section)
  end
  return result
end

return M
