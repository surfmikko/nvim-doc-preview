-- Sequence diagram model (free of Mermaid syntax, so a drawing stage can be
-- shared with PlantUML, doc/diagram-model.md 2).
--   Seq   { participants = {P...}, by_id, events = {E...} }
--   P     { id, label, kind = "participant"|"actor", src }
--   events (each with `src`, the 1-based source line):
--     message    { from, to, text, line = "solid"|"dashed",
--                  head = "arrow"|"open"|"cross"|"async",
--                  activate?, deactivate? }   (activate: target, deactivate: sender)
--     note       { side = "left"|"right"|"over", targets = {ids}, text }
--     activate   { id }   deactivate { id }
--     autonumber { off?, start?, step? }
--     block      { type = "loop"|"alt"|"opt"|"par"|"critical"|"break"|"rect",
--                  label, sections = { {label?, events = {E...}} } }
--                (section 1 is the body; later ones start at else/and/option)
local M = {}

function M.new()
  return { participants = {}, by_id = {}, events = {} }
end

-- Declare a participant, or on redeclaration replace its label and kind
-- when given. Implicit participants (first mention) pass neither.
---@param label? string  defaults to the id
---@param kind? string  defaults to "participant"
function M.add_participant(seq, id, label, kind, src)
  local p = seq.by_id[id]
  if p then
    p.label = label or p.label
    p.kind = kind or p.kind
    return p
  end
  p = { id = id, label = label or id, kind = kind or "participant", src = src }
  seq.participants[#seq.participants + 1] = p
  seq.by_id[id] = p
  return p
end

---@param list table[]  events array to append to
function M.add_event(list, event)
  list[#list + 1] = event
  return event
end

---@return table block  with its first (body) section
function M.new_block(type_, label, src)
  return { kind = "block", type = type_, label = label, src = src, sections = { { events = {} } } }
end

function M.add_section(block, label)
  block.sections[#block.sections + 1] = { label = label, events = {} }
  return block.sections[#block.sections]
end

return M
