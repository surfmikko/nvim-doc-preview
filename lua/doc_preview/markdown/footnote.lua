-- Markdown footnote definitions `[^label]: text` (GFM extension). The body is
-- the rest of the first line plus following lines indented by 4 columns (blank
-- lines allowed while the next non-blank line is still indented, lazy
-- paragraph continuation as in list items); it is scanned recursively, so it
-- holds blocks. A definition may interrupt a paragraph (cmark-gfm does not
-- exempt it, like an ATX heading). The label may not contain whitespace.
-- Reference: cmark-gfm footnotes extension behaviour (no code or text
-- copied; see doc/references.md).
local container = require("doc_preview.markdown.container")
local link_syntax = require("doc_preview.markdown.link_syntax")

local M = {}

local INDENT = 4

-- Key of the footnote label set inside the shared `refs` table. Normalised
-- link labels never start with a blank, so it cannot collide with one.
M.KEY = " footnotes"

-- Returns the normalised label and the rest of the first line when line starts
-- a definition (indent 0-3), else nil.
function M.start(line)
  local indent, at = container.expand_indent(line)
  if indent > 3 then
    return nil
  end
  local label, rest = line:sub(at):match("^%[%^([^%]%s]+)%]:(.*)$")
  if not label then
    return nil
  end
  return link_syntax.normalize(label), (rest:gsub("^[ \t]+", ""))
end

-- Records label in the set of defined footnotes (first definition wins).
function M.define(refs, label)
  refs[M.KEY] = refs[M.KEY] or {}
  refs[M.KEY][label] = true
end

function M.defined(refs, label)
  return refs[M.KEY] ~= nil and refs[M.KEY][label] == true
end

-- Normalised label when s[at..i] is `[^label]` for a defined footnote (at is
-- the "[", i the "]"), else nil.
function M.ref_label(s, at, i, refs)
  local label = s:sub(at + 1, i - 1):match("^%^([^%]%s]+)$")
  label = label and link_syntax.normalize(label)
  if label and M.defined(refs, label) then
    return label
  end
end

local function is_blank(line)
  return line:match("^%s*$") ~= nil
end

-- True when a non-indented line cannot continue the body lazily.
local function ends_body(line, inner, inner_nos, inner_lazy)
  return M.start(line) ~= nil or container.ends_item(line, inner, inner_nos, inner_lazy)
end

-- Collects the definition on line k0 (label, first line rest). `scan` is the
-- block scanner. Returns the pending entry and the index of the first line
-- after it.
function M.take(lines, linenos, lazy, k0, label, rest, scan)
  local inner, inner_nos, inner_lazy = { rest }, { linenos[k0] }, {}
  local j = k0 + 1
  while j <= #lines do
    local line = lines[j]
    if is_blank(line) then
      local n = container.next_nonblank(lines, j)
      if not n or container.expand_indent(lines[n]) < INDENT then
        break
      end
      for b = j, n - 1 do
        inner[#inner + 1] = ""
        inner_nos[#inner] = linenos[b]
      end
      j = n
    else
      if container.expand_indent(line) >= INDENT then
        inner[#inner + 1] = container.strip_columns(line, INDENT)
        inner_lazy[#inner] = lazy[j]
      elseif ends_body(line, inner, inner_nos, inner_lazy) then
        break
      else
        inner[#inner + 1] = line
        inner_lazy[#inner] = true
      end
      inner_nos[#inner] = linenos[j]
      j = j + 1
    end
  end
  local children, open = scan(inner, inner_nos, inner_lazy)
  return {
    footnote = true,
    label = label,
    children = children,
    open = open,
    start = linenos[k0],
    last = inner_nos[#inner],
  },
    j
end

return M
