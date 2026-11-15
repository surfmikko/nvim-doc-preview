-- Markdown code blocks: fenced code (backtick and tilde fences) and indented
-- code. Pure line helpers plus take_fence and take_indented, which collect
-- one block from the scanned lines.
-- Reference: CommonMark spec, sections "Fenced code blocks" and "Indented
-- code blocks" (behaviour only,
-- no code or text copied; see doc/references.md).
local container = require("doc_preview.markdown.container")
local unescape = require("doc_preview.markdown.unescape")

local M = {}

-- First word of the info string, unescaped; empty gives nil.
local function lang_of(info)
  local word = info:match("^%s*(%S+)")
  if not word then
    return nil
  end
  return unescape.unescape(word)
end

-- Returns { char, len, indent, lang } for a fence opener line, else nil.
function M.fence_open(line)
  local indent, at = container.expand_indent(line)
  if indent > 3 then
    return nil
  end
  local fence, info = line:sub(at):match("^(```+)(.*)$")
  if not fence then
    fence, info = line:sub(at):match("^(~~~+)(.*)$")
  elseif info:find("`", 1, true) then
    return nil
  end
  if not fence then
    return nil
  end
  return { char = fence:sub(1, 1), len = #fence, indent = indent, lang = lang_of(info) }
end

-- True when `line` closes the fence `open`.
function M.fence_close(line, open)
  local indent, at = container.expand_indent(line)
  if indent > 3 then
    return false
  end
  local fence = line:sub(at):match("^(" .. open.char:rep(3) .. "+)[ \t]*$")
  return fence ~= nil and #fence >= open.len
end

-- Collects the fence opened at lines[k]; returns the pending entry and the
-- index of the first line after it. An unclosed fence runs to the last line.
function M.take_fence(lines, linenos, k, open)
  local body, j = {}, k + 1
  while j <= #lines and not M.fence_close(lines[j], open) do
    body[#body + 1] = container.strip_columns(lines[j], open.indent)
    j = j + 1
  end
  local last = math.min(j, #lines)
  local entry = {
    code = true,
    fenced = true,
    lang = open.lang,
    lines = body,
    start = linenos[k],
    last = linenos[last],
    body = linenos[k] + 1,
  }
  return entry, j + 1
end

-- True when `line` starts or continues indented code (4+ columns, not blank).
function M.is_indented(line)
  return not line:match("^%s*$") and container.expand_indent(line) >= 4
end

-- Collects the indented code run starting at lines[k]; returns the pending
-- entry and the index of the first line after it. Blank lines stay inside
-- the run only when more indented code follows.
function M.take_indented(lines, linenos, k)
  local body, last, j = {}, k, k
  while j <= #lines and (M.is_indented(lines[j]) or lines[j]:match("^%s*$")) do
    body[#body + 1] = container.strip_columns(lines[j], 4)
    if M.is_indented(lines[j]) then
      last = j
    end
    j = j + 1
  end
  for i = #body, last - k + 2, -1 do
    body[i] = nil
  end
  local entry = {
    code = true,
    fenced = false,
    lines = body,
    start = linenos[k],
    last = linenos[last],
    body = linenos[k],
  }
  return entry, last + 1
end

return M
