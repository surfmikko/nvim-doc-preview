-- document.model node constructors and validation (doc/document-model.md).
-- Only the kinds needed so far; the registry grows with each slice.
local M = {}

-- Inline nodes carry no source range (architecture 4.2).
M.inline_kinds = {
  text = true,
  emph = true,
  strong = true,
  strike = true,
  code = true,
  softbreak = true,
  hardbreak = true,
  link = true,
  image = true,
  html_inline = true,
  footnote_ref = true,
}

M.kinds = {
  document = true,
  heading = true,
  paragraph = true,
  thematic_break = true,
  code_block = true,
  html_block = true,
  blockquote = true,
  list = true,
  list_item = true,
  table = true,
  footnote_def = true,
}
for kind in pairs(M.inline_kinds) do
  M.kinds[kind] = true
end

function M.text(value)
  return { kind = "text", value = value }
end

function M.emph(inlines)
  return { kind = "emph", inlines = inlines }
end

function M.strong(inlines)
  return { kind = "strong", inlines = inlines }
end

function M.strike(inlines)
  return { kind = "strike", inlines = inlines }
end

function M.code(value)
  return { kind = "code", value = value }
end

function M.softbreak()
  return { kind = "softbreak" }
end

function M.hardbreak()
  return { kind = "hardbreak" }
end

function M.link(target, title, inlines)
  return { kind = "link", target = target, title = title, inlines = inlines }
end

function M.footnote_def(label, children, src_start, src_end)
  return {
    kind = "footnote_def",
    label = label,
    children = children,
    src_start = src_start,
    src_end = src_end,
  }
end

function M.footnote_ref(label)
  return { kind = "footnote_ref", label = label }
end

-- `alt` is the plain text of the image description.
function M.image(target, title, alt)
  return { kind = "image", target = target, title = title, alt = alt }
end

-- Raw inline HTML, kept verbatim and atomic.
function M.html_inline(value)
  return { kind = "html_inline", value = value }
end

function M.paragraph(inlines, src_start, src_end)
  return { kind = "paragraph", inlines = inlines, src_start = src_start, src_end = src_end }
end

function M.heading(level, inlines, src_start, src_end)
  assert(
    type(level) == "number" and level >= 1 and level <= 6 and level % 1 == 0,
    "heading level must be 1-6"
  )
  return {
    kind = "heading",
    level = level,
    inlines = inlines,
    src_start = src_start,
    src_end = src_end,
  }
end

function M.thematic_break(src_start, src_end)
  return { kind = "thematic_break", src_start = src_start, src_end = src_end }
end

-- `lines` are the verbatim body lines; `src_body` is the source line of
-- lines[1] (later lines follow contiguously).
function M.code_block(lang, lines, src_body, src_start, src_end)
  return {
    kind = "code_block",
    lang = lang,
    lines = lines,
    src_body = src_body,
    src_start = src_start,
    src_end = src_end,
  }
end

-- Raw HTML block: `lines` verbatim (indent kept), `src_body` as in code_block.
function M.html_block(lines, src_body, src_start, src_end)
  return {
    kind = "html_block",
    lines = lines,
    src_body = src_body,
    src_start = src_start,
    src_end = src_end,
  }
end

function M.blockquote(children, src_start, src_end)
  return { kind = "blockquote", children = children, src_start = src_start, src_end = src_end }
end

-- `tight` decides blank lines between items; `start` is the first number.
function M.list(ordered, start, tight, items, src_start, src_end)
  return {
    kind = "list",
    ordered = ordered,
    start = start,
    tight = tight,
    children = items,
    src_start = src_start,
    src_end = src_end,
  }
end

-- `checked` is nil (not a task), true or false.
function M.list_item(checked, children, src_start, src_end)
  return {
    kind = "list_item",
    checked = checked,
    children = children,
    src_start = src_start,
    src_end = src_end,
  }
end

-- `align` entries nil/"left"/"center"/"right"; `header` and each row a list of
-- `{ inlines }` cells, `#align` per row. Header is src_start, the delimiter
-- row src_start + 1, body row i src_start + 1 + i.
function M.table(align, header, rows, src_start, src_end)
  return {
    kind = "table",
    align = align,
    header = header,
    rows = rows,
    src_start = src_start,
    src_end = src_end,
  }
end

-- Block image: a paragraph that is exactly one image (see M.image).
function M.image_block(target, title, alt, src_start, src_end)
  return {
    kind = "image",
    block = true,
    target = target,
    title = title,
    alt = alt,
    src_start = src_start,
    src_end = src_end,
  }
end

function M.document(children, src_start, src_end)
  return { kind = "document", children = children, src_start = src_start, src_end = src_end }
end

local ALIGNS = { left = true, center = true, right = true }

local function validate_row(row, n)
  if type(row) ~= "table" or #row ~= n then
    return false, "table row must have " .. n .. " cells"
  end
  for _, cell in ipairs(row) do
    if type(cell.inlines) ~= "table" then
      return false, "table cell lacks inlines"
    end
    for _, inline in ipairs(cell.inlines) do
      local ok, err = M.validate(inline)
      if not ok then
        return false, err
      end
    end
  end
  return true
end

local function validate_table(node)
  local n = #node.header
  for i = 1, n do
    local a = node.align[i]
    if a ~= nil and not ALIGNS[a] then
      return false, "table align must be left, center or right"
    end
  end
  local ok, err = validate_row(node.header, n)
  for _, row in ipairs(node.rows) do
    if ok then
      ok, err = validate_row(row, n)
    end
  end
  return ok, err
end

-- Returns true, or false plus a message for the first invalid node.
local function validate_footnote(node)
  if type(node.label) ~= "string" or node.label == "" then
    return false, node.kind .. " needs a non-empty label"
  end
  if node.kind == "footnote_def" and type(node.children) ~= "table" then
    return false, "footnote_def needs children"
  end
  return true
end

local function validate_image(node)
  if type(node.alt) ~= "string" or node.target == nil then
    return false, "image needs alt string and target"
  end
  if node.block and not (node.src_start and node.src_end) then
    return false, "image lacks src_start/src_end"
  end
  return true
end

local function validate_lines(node)
  if type(node.lines) ~= "table" then
    return false, node.kind .. " lines must be a table"
  end
  for _, line in ipairs(node.lines) do
    if type(line) ~= "string" then
      return false, node.kind .. " lines must be strings"
    end
  end
  return true
end

local function validate_html_inline(node)
  if type(node.value) ~= "string" then
    return false, "html_inline value must be a string"
  end
  return true
end

-- Kind-specific checks, run after the source-range check.
local KIND_VALIDATORS = {
  code_block = validate_lines,
  html_block = validate_lines,
  footnote_ref = validate_footnote,
  footnote_def = validate_footnote,
  html_inline = validate_html_inline,
  table = validate_table,
}

local function has_range(node)
  return M.inline_kinds[node.kind] or (node.src_start and node.src_end)
end

local function validate_children(node)
  for _, child in ipairs(node.children or node.inlines or {}) do
    local ok, err = M.validate(child)
    if not ok then
      return false, err
    end
  end
  return true
end

function M.validate(node)
  if not M.kinds[node.kind] then
    return false, "unknown kind: " .. tostring(node.kind)
  end
  if node.kind == "image" then
    return validate_image(node)
  end
  if not has_range(node) then
    return false, node.kind .. " lacks src_start/src_end"
  end
  local check = KIND_VALIDATORS[node.kind]
  if check then
    local ok, err = check(node)
    if not ok then
      return false, err
    end
  end
  return validate_children(node)
end

return M
