-- Frontend for standalone diagram files (doc/architecture.md 6.3): the whole
-- buffer is one `code_block{lang="mermaid"}`, so the shared renderer, its
-- safe() path and the source map are reused.
local model = require("doc_preview.document.model")

local M = {}

-- Filetype `mermaid` or a `.mmd`/`.mermaid` name; no global vim.filetype.add.
---@param ft string
---@param name string
function M.matches(ft, name)
  return ft == "mermaid" or name:match("%.mmd$") ~= nil or name:match("%.mermaid$") ~= nil
end

---@param lines string[]
---@return table document
function M.parse(lines)
  local last = math.max(#lines, 1)
  local block = model.code_block("mermaid", lines, 1, 1, last)
  return model.document({ block }, 1, last)
end

return M
