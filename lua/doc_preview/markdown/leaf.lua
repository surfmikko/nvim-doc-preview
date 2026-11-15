-- Markdown leaf line classifiers shared by the block scanner and the
-- containers: ATX headings, setext underlines, thematic breaks.
-- Reference: CommonMark spec, sections "ATX headings", "Setext headings",
-- "Thematic breaks" (behaviour only, no code or text copied; see
-- doc/references.md).
local container = require("doc_preview.markdown.container")

local M = {}

local function trim(s)
  return (s:gsub("^[ \t]+", ""):gsub("[ \t]+$", ""))
end

-- Trailing blanks stay: two of them before a newline are a hard break.
function M.clean(line)
  return (line:gsub("^ ? ? ?", ""))
end

-- Returns level, content for an ATX heading line, else nil.
function M.atx(line)
  local indent, at = container.expand_indent(line)
  if indent > 3 then
    return nil
  end
  local hashes, rest = line:sub(at):match("^(#+)(.*)$")
  if not hashes or #hashes > 6 or not (rest == "" or rest:match("^[ \t]")) then
    return nil
  end
  local content = trim(rest)
  if content:match("^#+$") then
    content = ""
  else
    content = trim(content:gsub("[ \t]+#+$", ""))
  end
  return #hashes, content
end

-- Returns 1 or 2 for a setext underline line, else nil.
function M.setext(line)
  local indent, at = container.expand_indent(line)
  if indent > 3 then
    return nil
  end
  local rest = line:sub(at)
  if rest:match("^=+[ \t]*$") then
    return 1
  end
  -- A plain `-` run is an underline here; spaced runs fall to thematic().
  if rest:match("^%-+[ \t]*$") then
    return 2
  end
end

-- True for a thematic break line: 3+ of one of `*-_`, blanks allowed between.
function M.thematic(line)
  local indent, at = container.expand_indent(line)
  if indent > 3 then
    return false
  end
  local rest = line:sub(at):gsub("[ \t]+$", "")
  local c = rest:sub(1, 1)
  if c ~= "*" and c ~= "-" and c ~= "_" then
    return false
  end
  local only = rest:gsub("[ \t]", "")
  return #only >= 3 and not only:find("[^" .. c .. "]")
end

return M
