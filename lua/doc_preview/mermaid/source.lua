-- Mermaid source preamble: blank lines, `---` frontmatter, `%%` comments and
-- `%%{...}%%` directives before the diagram header.
local M = {}

-- Index of the line after a `---` frontmatter block starting at `i`, else `i`.
local function skip_frontmatter(lines, i)
  if not (lines[i] or ""):match("^%-%-%-%s*$") then
    return i
  end
  for j = i + 1, #lines do
    if lines[j]:match("^%-%-%-%s*$") then
      return j + 1
    end
  end
  return i
end

-- Index of the line after a `%%{ ... }%%` directive starting at `i`.
local function skip_directive(lines, i)
  for j = i, #lines do
    if lines[j]:find("}%%", 1, true) then
      return j + 1
    end
  end
  return #lines + 1
end

---@param lines string[]
---@return integer  index of the first content line, #lines + 1 if none
function M.first_content(lines)
  local i = 1
  -- frontmatter is only valid before any other content
  while lines[i] and lines[i]:match("^%s*$") do
    i = i + 1
  end
  i = skip_frontmatter(lines, i)
  while i <= #lines do
    local l = lines[i]
    if l:match("^%s*$") or (l:match("^%s*%%%%") and not l:match("^%s*%%%%{")) then
      i = i + 1
    elseif l:match("^%s*%%%%{") then
      i = skip_directive(lines, i)
    else
      return i
    end
  end
  return i
end

return M
