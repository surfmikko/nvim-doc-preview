-- Markdown block pass: ATX and setext headings, thematic breaks, fenced and
-- indented code (markdown/code), HTML blocks (markdown/html, verbatim,
-- never lazily continued), block quotes
-- and lists (nested, tight/loose, GFM task items; markdown/container: inner
-- lines are scanned by the same function with a map back to source lines,
-- lazy paragraph continuation) and paragraphs (inline content via
-- markdown/inline), pipe tables (markdown/table: a delimiter row under a
-- header line that ends the open paragraph; top level and, through the
-- recursive scan, inside containers); every other block kind still falls back to
-- a paragraph until its slice lands. Two passes: link reference definitions
-- (leading lines of paragraphs) are collected first, because a reference may
-- precede its definition; then all inline text is parsed.
-- Reference: CommonMark spec, sections "ATX headings", "Setext headings",
-- "Thematic breaks", "Fenced code blocks", "Indented code blocks", "HTML blocks", "Block quotes", "List items", "Lists", "Paragraphs", "Tabs", GFM "Tables (extension)" (behaviour only, no code or text copied; see
-- doc/references.md).
local model = require("doc_preview.document.model")
local inline = require("doc_preview.markdown.inline")
local link_syntax = require("doc_preview.markdown.link_syntax")
local container = require("doc_preview.markdown.container")
local code = require("doc_preview.markdown.code")
local html = require("doc_preview.markdown.html")
local footnote = require("doc_preview.markdown.footnote")
local leaf = require("doc_preview.markdown.leaf")
local scan_mod = require("doc_preview.markdown.scan")

local M = {}

M.expand_indent = container.expand_indent

local build

local NOT_PARAGRAPH = { "quote", "list", "rule", "code", "html", "table", "level", "footnote" }

local function is_paragraph(p)
  for _, kind in ipairs(NOT_PARAGRAPH) do
    if p[kind] then
      return false
    end
  end
  return true
end

-- GFM task box at the start of an item's first paragraph: strips it and
-- returns checked (true/false), else nil.
local function take_task_box(children)
  local first = children[1]
  if not first or not is_paragraph(first) then
    return nil
  end
  local mark, after = first.text:match("^%[([ xX])%]()")
  if not mark or (after <= #first.text and not first.text:sub(after, after):match("%s")) then
    return nil
  end
  first.text = first.text:sub(after + 1)
  return mark ~= " "
end

local function build_list(p, refs)
  local items = {}
  for _, it in ipairs(p.items) do
    local checked = take_task_box(it.children)
    items[#items + 1] = model.list_item(checked, build(it.children, refs), it.start, it.last)
  end
  return model.list(p.ordered, p.ordered and p.number or nil, p.tight, items, p.start, p.last)
end

local function build_cells(texts, refs)
  local cells = {}
  for i, text in ipairs(texts) do
    cells[i] = { inlines = inline.parse(text, refs) }
  end
  return cells
end

local function build_table(p, refs)
  local rows = {}
  for i, row in ipairs(p.rows) do
    rows[i] = build_cells(row, refs)
  end
  return model.table(p.align, build_cells(p.header, refs), rows, p.start, p.last)
end

-- A paragraph whose only inline is an image becomes the block image.
local function paragraph_or_image(p, refs)
  local inlines = inline.parse(p.text, refs)
  local only = inlines[1]
  if #inlines == 1 and only.kind == "image" then
    return model.image_block(only.target, only.title, only.alt, p.start, p.last)
  end
  return model.paragraph(inlines, p.start, p.last)
end

local function build_quote(p, refs)
  return model.blockquote(build(p.children, refs), p.start, p.last)
end

local function build_footnote(p, refs)
  return model.footnote_def(p.label, build(p.children, refs), p.start, p.last)
end

local function build_code(p)
  return model.code_block(p.lang, p.lines, p.body, p.start, p.last)
end

local function build_html(p)
  return model.html_block(p.lines, p.body, p.start, p.last)
end

local function build_rule(p)
  return model.thematic_break(p.start, p.last)
end

local function build_heading(p, refs)
  return model.heading(p.level, inline.parse(p.text, refs), p.start, p.last)
end

local BUILDERS = {
  { "quote", build_quote },
  { "list", build_list },
  { "footnote", build_footnote },
  { "code", build_code },
  { "html", build_html },
  { "table", build_table },
  { "rule", build_rule },
  { "level", build_heading },
}

local function build_block(p, refs)
  for _, b in ipairs(BUILDERS) do
    if p[b[1]] then
      return b[2](p, refs)
    end
  end
  if p.text ~= "" then
    return paragraph_or_image(p, refs)
  end
end

-- Pass 2: inline parsing of the collected blocks.
function build(pending, refs)
  local blocks = {}
  for _, p in ipairs(pending) do
    blocks[#blocks + 1] = build_block(p, refs)
  end
  return blocks
end

local collect_definitions

local function collect_list(p, refs)
  for _, it in ipairs(p.items) do
    collect_definitions(it.children, refs)
  end
end

local function has_definitions(p)
  return not (p.level or p.rule or p.code or p.html or p.table)
end

local function collect_definition(p, refs)
  local consumed
  p.text, consumed = link_syntax.extract(p.text, refs)
  p.start = p.start + consumed
end

-- Pass 1b: definitions at the start of paragraphs, in document order; refs is
-- shared by every nesting level.
function collect_definitions(pending, refs)
  for _, p in ipairs(pending) do
    if p.quote then
      collect_definitions(p.children, refs)
    elseif p.list then
      collect_list(p, refs)
    elseif p.footnote then
      footnote.define(refs, p.label)
      collect_definitions(p.children, refs)
    elseif has_definitions(p) then
      collect_definition(p, refs)
    end
  end
end

---@param lines string[]
---@return table document
function M.parse(lines)
  local linenos = {}
  for i = 1, #lines do
    linenos[i] = i
  end
  local pending = scan_mod.scan(lines, linenos, {})
  local refs = {}
  collect_definitions(pending, refs)
  return model.document(build(pending, refs), 1, math.max(#lines, 1))
end

container.setup(scan_mod.scan, leaf.atx, leaf.thematic, code.fence_open, html.block_start)

return M
