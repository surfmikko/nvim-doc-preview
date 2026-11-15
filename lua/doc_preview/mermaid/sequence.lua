-- Mermaid sequence diagram: parse to mermaid/sequence_model (statement
-- syntax in sequence_syntax.lua), then lay out and draw with
-- sequence_layout / sequence_draw (shared with PlantUML).
local draw = require("doc_preview.mermaid.sequence_draw")
local errbox = require("doc_preview.core.errbox")
local layout = require("doc_preview.mermaid.sequence_layout")
local model = require("doc_preview.mermaid.sequence_model")
local source = require("doc_preview.mermaid.source")
local syntax = require("doc_preview.mermaid.sequence_syntax")

local M = {}

local function fail(lnum, msg)
  error(("line %d: %s"):format(lnum, msg), 0)
end

-- Participants mentioned by an event exist from their first mention.
local function mention(seq, ids, lnum)
  for _, id in ipairs(ids) do
    model.add_participant(seq, id, nil, nil, lnum)
  end
end

local function current(st)
  local top = st.stack[#st.stack]
  if top then
    return top.block.sections[#top.block.sections].events
  end
  return st.seq.events
end

local function emit(st, event, lnum)
  event.src = lnum
  model.add_event(current(st), event)
end

local function parse_participant(st, stmt, lnum)
  local p = syntax.participant(stmt)
  if not p then
    return false
  end
  model.add_participant(st.seq, p.id, p.label, p.kind, lnum)
  return true
end

-- Events that mention participants: messages, notes, activation.
local function parse_event(st, stmt, lnum)
  local ev = syntax.message(stmt)
    or syntax.note(stmt)
    or syntax.activation(stmt)
    or syntax.autonumber(stmt)
  if not ev then
    return false
  end
  if ev.kind == "message" then
    mention(st.seq, { ev.from, ev.to }, lnum)
  elseif ev.kind == "note" then
    mention(st.seq, ev.targets, lnum)
  elseif ev.id then
    mention(st.seq, { ev.id }, lnum)
  end
  emit(st, ev, lnum)
  return true
end

local function parse_block(st, stmt, lnum)
  local type_, label = syntax.block_open(stmt)
  if not type_ then
    return false
  end
  local block = model.new_block(type_, label, lnum)
  if type_ ~= "box" then
    emit(st, block, lnum)
  end
  st.stack[#st.stack + 1] = { block = block, line = lnum }
  return true
end

local function parse_section(st, stmt, lnum)
  local kw, owner, label = syntax.section(stmt)
  if not kw then
    return false
  end
  local top = st.stack[#st.stack]
  if not top or top.block.type ~= owner then
    fail(lnum, kw .. " outside " .. owner)
  end
  model.add_section(top.block, label)
  return true
end

local function parse_end(st, stmt, lnum)
  if stmt ~= "end" then
    return false
  end
  if #st.stack == 0 then
    fail(lnum, "end without block")
  end
  st.stack[#st.stack] = nil
  return true
end

local PARSERS = { parse_end, parse_participant, parse_event, parse_block, parse_section }

local function parse_statement(st, stmt, lnum)
  for _, p in ipairs(PARSERS) do
    if p(st, stmt, lnum) then
      return
    end
  end
  if not syntax.ignored(stmt) then
    fail(lnum, "syntax error: " .. stmt)
  end
end

local function check_header(stmt, lnum)
  if stmt ~= "sequenceDiagram" then
    fail(lnum, "expected sequenceDiagram")
  end
end

-- Parse the source into a Seq; raises a plain string on a syntax error.
---@param lines string[]
---@return table seq
function M.parse(lines)
  local start = source.first_content(lines)
  local st = { seq = model.new(), stack = {} }
  local seen_header = false
  for i = start, #lines do
    if not lines[i]:match("^%s*%%%%") then
      for _, raw in ipairs(vim.split(lines[i], ";", { plain = true })) do
        local stmt = raw:match("^%s*(.-)%s*$")
        if stmt ~= "" and seen_header then
          parse_statement(st, stmt, i)
        elseif stmt ~= "" then
          check_header(stmt, i)
          seen_header = true
        end
      end
    end
  end
  local open = st.stack[#st.stack]
  if open then
    fail(open.line, open.block.type .. " is not closed")
  end
  return st.seq
end

-- Attempts in order: normal spacing (compact when ctx.compact), compact
-- spacing, then compact with message and note text wrapped to these widths.
local WRAPS = { 30, 20, 14, 10, 6 }

local function attempts(ctx)
  local list = { { compact = ctx.compact }, { compact = true } }
  for _, wrap in ipairs(WRAPS) do
    list[#list + 1] = { compact = true, wrap = wrap }
  end
  return list
end

-- Width policy (doc/diagram-model.md 1): the first attempt whose drawing
-- fits ctx.width wins, else the boxed source with a note. Below the errbox
-- minimum width the clipped, most wrapped drawing is returned.
---@param lines string[]
---@param ctx { width: integer, charset?: string, compact?: boolean }
---@return doc_preview.Output
function M.render(lines, ctx)
  local seq = M.parse(lines)
  if #seq.participants == 0 then
    error("no participants", 0)
  end
  local lay
  for _, opts in ipairs(attempts(ctx)) do
    lay = layout.layout(seq, opts)
    if lay.width <= ctx.width then
      return draw.draw(lay, ctx)
    end
  end
  if ctx.width < 5 then
    return draw.draw(lay, ctx)
  end
  return errbox.render(lines, ctx, ("diagram wider than %d columns"):format(ctx.width))
end

return M
