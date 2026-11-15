-- Test-only projection: document.model -> CommonMark-style HTML, so parsed
-- input can be compared with the HTML `cmark` produces (doc/testing.md 3).
-- No Neovim API.
local M = {}

M.UNSUPPORTED = "<!--unsupported:%s-->"

local function escape(s)
  return (s:gsub('[&<>"]', { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" }))
end

-- cmark's href escaping: keep URL-safe bytes, `&` and `'` as entities,
-- percent-encode the rest.
local function href(s)
  return (
    s:gsub("[^%w%-_.+!*(),%%#@?=;:/$~&']", function(c)
      return string.format("%%%02X", c:byte())
    end)
      :gsub("&", "&amp;")
      :gsub("'", "&#x27;")
  )
end

local function title_attr(title)
  return title and (' title="' .. escape(title) .. '"') or ""
end

local function img_html(n)
  return string.format(
    '<img src="%s" alt="%s"%s />',
    href(n.target),
    escape(n.alt),
    title_attr(n.title)
  )
end

-- Footnote state of the projection in progress (reset by M.project):
-- defs by label, numbers by label in order of first use, refs per number.
local fn = { defs = {}, numbers = {}, order = {}, refs = {} }

local BACKREFS = "@@backrefs:%d@@"

local function collect_defs(children)
  for _, node in ipairs(children) do
    if node.kind == "footnote_def" and not fn.defs[node.label] then
      fn.defs[node.label] = node
    end
    if node.children then
      collect_defs(node.children)
    end
  end
end

-- cmark-gfm form.
local function ref_html(label)
  if not fn.defs[label] then
    return escape("[^" .. label .. "]")
  end
  local n = fn.numbers[label]
  if not n then
    fn.order[#fn.order + 1] = label
    n = #fn.order
    fn.numbers[label] = n
    fn.refs[n] = 0
  end
  fn.refs[n] = fn.refs[n] + 1
  return string.format(
    '<sup class="footnote-ref"><a href="#fn-%s" id="fnref-%s" data-footnote-ref>%d</a></sup>',
    escape(label),
    escape(label) .. (fn.refs[n] == 1 and "" or "-" .. fn.refs[n]),
    n
  )
end

local tags = { emph = "em", strong = "strong", strike = "del" }

local function inline_html(inlines)
  local parts = {}
  for _, n in ipairs(inlines) do
    if n.kind == "text" then
      parts[#parts + 1] = escape(n.value)
    elseif n.kind == "code" then
      parts[#parts + 1] = "<code>" .. escape(n.value) .. "</code>"
    elseif n.kind == "html_inline" then
      parts[#parts + 1] = n.value
    elseif n.kind == "softbreak" then
      parts[#parts + 1] = "\n"
    elseif n.kind == "hardbreak" then
      parts[#parts + 1] = "<br />\n"
    elseif n.kind == "link" then
      parts[#parts + 1] = string.format(
        '<a href="%s"%s>%s</a>',
        href(n.target),
        title_attr(n.title),
        inline_html(n.inlines)
      )
    elseif n.kind == "image" then
      parts[#parts + 1] = img_html(n)
    elseif n.kind == "footnote_ref" then
      parts[#parts + 1] = ref_html(n.label)
    else
      parts[#parts + 1] =
        string.format("<%s>%s</%s>", tags[n.kind], inline_html(n.inlines), tags[n.kind])
    end
  end
  return table.concat(parts)
end

local block_html

local function tight_part(node, tight)
  if tight and node.kind == "paragraph" then
    return inline_html(node.inlines)
  elseif tight and node.kind == "image" then
    return img_html(node)
  end
end

local function blocks_html(children, unsupported, tight)
  local parts = {}
  for _, node in ipairs(children) do
    -- footnote definitions are projected in the trailing section
    if node.kind ~= "footnote_def" then
      parts[#parts + 1] = tight_part(node, tight) or block_html(node, unsupported)
    end
  end
  return table.concat(parts, "\n")
end

-- cmark-gfm --extension tasklist form.
local function checkbox(checked)
  return '<input type="checkbox"' .. (checked and ' checked=""' or "") .. ' disabled="" /> '
end

-- cmark layout: a tight paragraph is bare, any other block sits on its own lines.
local function item_html(item, unsupported, tight)
  local kids = item.children
  local inner = blocks_html(kids, unsupported, tight)
  local box = item.checked ~= nil and checkbox(item.checked) or ""
  local first, last = kids[1], kids[#kids]
  local function bare(n)
    return tight and n and (n.kind == "paragraph" or n.kind == "image")
  end
  local bare_first, bare_last = bare(first), bare(last)
  return "<li>"
    .. box
    .. ((first and not bare_first) and "\n" or "")
    .. inner
    .. ((last and not bare_last) and "\n" or "")
    .. "</li>"
end

local function list_html(node, unsupported)
  local tag = node.ordered and "ol" or "ul"
  local attr = (node.ordered and node.start ~= 1) and (' start="' .. node.start .. '"') or ""
  local parts = { "<" .. tag .. attr .. ">" }
  for _, item in ipairs(node.children) do
    parts[#parts + 1] = item_html(item, unsupported, node.tight)
  end
  parts[#parts + 1] = "</" .. tag .. ">"
  return table.concat(parts, "\n")
end

local function code_html(node)
  local attr = (node.lang and node.lang ~= "") and (' class="language-' .. escape(node.lang) .. '"')
    or ""
  local body = {}
  for _, line in ipairs(node.lines) do
    body[#body + 1] = escape(line) .. "\n"
  end
  return "<pre><code" .. attr .. ">" .. table.concat(body) .. "</code></pre>"
end

local function raw_html(node)
  local body = {}
  for _, line in ipairs(node.lines) do
    body[#body + 1] = line .. "\n"
  end
  return table.concat(body)
end

-- cmark-gfm --extension table form, one tag per line. No <tbody> without
-- body rows.
local function row_html(cells, align, tag)
  local parts = { "<tr>" }
  for i, cell in ipairs(cells) do
    local attr = align[i] and (' align="' .. align[i] .. '"') or ""
    parts[#parts + 1] = "<" .. tag .. attr .. ">" .. inline_html(cell.inlines) .. "</" .. tag .. ">"
  end
  parts[#parts + 1] = "</tr>"
  return table.concat(parts, "\n")
end

local function table_html(node)
  local parts = { "<table>", "<thead>", row_html(node.header, node.align, "th"), "</thead>" }
  if #node.rows > 0 then
    parts[#parts + 1] = "<tbody>"
    for _, row in ipairs(node.rows) do
      parts[#parts + 1] = row_html(row, node.align, "td")
    end
    parts[#parts + 1] = "</tbody>"
  end
  parts[#parts + 1] = "</table>"
  return table.concat(parts, "\n")
end

local function heading_html(node)
  local tag = "h" .. node.level
  return string.format("<%s>%s</%s>", tag, inline_html(node.inlines), tag)
end

local function quote_html(node, unsupported)
  local inner = blocks_html(node.children, unsupported)
  return "<blockquote>\n" .. (inner == "" and "" or inner .. "\n") .. "</blockquote>"
end

local block_projectors = {
  heading = heading_html,
  image = function(node)
    return "<p>" .. img_html(node) .. "</p>"
  end,
  paragraph = function(node)
    return "<p>" .. inline_html(node.inlines) .. "</p>"
  end,
  thematic_break = function()
    return "<hr />"
  end,
  blockquote = quote_html,
  code_block = code_html,
  html_block = raw_html,
  list = list_html,
  table = table_html,
}

function block_html(node, unsupported)
  local project = block_projectors[node.kind]
  if project then
    return project(node, unsupported)
  end
  unsupported[#unsupported + 1] = node.kind
  return M.UNSUPPORTED:format(node.kind)
end

local function backref_link(n, label, k, bare)
  local idx = k == 1 and tostring(n) or (n .. "-" .. k)
  local sup = k == 1 and "" or ('<sup class="footnote-ref">' .. k .. "</sup>")
  return string.format(
    (bare and "" or " ")
      .. '<a href="#fnref-%s" class="footnote-backref" data-footnote-backref'
      .. ' data-footnote-backref-idx="%s" aria-label="Back to reference %s">\u{21A9}%s</a>',
    label .. (k == 1 and "" or "-" .. k),
    idx,
    idx,
    sup
  )
end

-- Entry body with a placeholder for the back-references, which are known
-- only once every body has been projected (bodies may hold references).
local bare_ref = {}

local function entry_html(def, unsupported, n)
  local kids = def.children
  local last = kids[#kids]
  local mark = BACKREFS:format(n)
  local head = {}
  for i = 1, #kids - 1 do
    head[i] = kids[i]
  end
  local out = blocks_html(head, unsupported)
  local tail
  if last and last.kind == "paragraph" then
    tail = "<p>" .. inline_html(last.inlines) .. mark .. "</p>"
  else
    bare_ref[n] = true
    tail = (last and (block_html(last, unsupported) .. "\n") or "") .. mark
  end
  return '<li id="fn-'
    .. escape(def.label)
    .. '">\n'
    .. (out ~= "" and out .. "\n" or "")
    .. tail
    .. "\n</li>"
end

local function section_html(unsupported)
  local items = {}
  local i = 1
  while i <= #fn.order do
    local label = fn.order[i]
    items[i] = entry_html(fn.defs[label], unsupported, i)
    i = i + 1
  end
  if #items == 0 then
    return ""
  end
  local html = table.concat(items, "\n")
  for n, label in ipairs(fn.order) do
    local links = {}
    for k = 1, fn.refs[n] do
      links[k] = backref_link(n, escape(label), k, bare_ref[n] and k == 1)
    end
    html =
      html:gsub((BACKREFS:format(n):gsub("%p", "%%%0")), (table.concat(links):gsub("%%", "%%%%")))
  end
  return '<section class="footnotes" data-footnotes>\n<ol>\n' .. html .. "\n</ol>\n</section>"
end

---@param doc table document node
---@return string html
---@return string[] unsupported kinds met, in order
function M.project(doc)
  local unsupported = {}
  fn = { defs = {}, numbers = {}, order = {}, refs = {} }
  bare_ref = {}
  collect_defs(doc.children)
  local body = blocks_html(doc.children, unsupported)
  local section = section_html(unsupported)
  if section ~= "" then
    body = body .. (body ~= "" and "\n" or "") .. section
  end
  return body, unsupported
end

-- Same on both sides: unify line endings, drop trailing blanks, collapse
-- blank lines, drop the final newline.
function M.normalize(html)
  local lines = {}
  for line in (html:gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
    line = line:gsub("[ \t]+$", "")
    if line ~= "" then
      lines[#lines + 1] = line
    end
  end
  return table.concat(lines, "\n")
end

return M
