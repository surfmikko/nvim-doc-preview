-- Mermaid state diagram: parse to graph.model (syntax tokens in
-- state_syntax.lua). States are `round` nodes; `[*]` becomes a `start` node
-- (as a transition source) or an `end` node (as a target), one pair per scope
-- with ids `start:<scope>`/`end:<scope>` (scope = composite id or `root`).
-- `<<choice>>` is `choice`, `<<fork>>`/`<<join>>` are `bar`. Description
-- lines (`id : text`) become node.rows = { { lines } }. A composite is a
-- subgraph with no node of its own; `--` inside it splits it into unnamed
-- region subgraphs `X--1`, `X--2` (empty title), children of the composite.
-- Notes are `record` nodes `note:N` joined to their state by a dotted edge
-- without ends. Styling statements are ignored.
-- render() draws through the shared width policy (mermaid/fit.lua).
local fit = require("doc_preview.mermaid.fit")
local model = require("doc_preview.graph.model")
local source = require("doc_preview.mermaid.source")
local syntax = require("doc_preview.mermaid.state_syntax")

local M = {}

local IGNORED = {
  classDef = true,
  class = true,
  style = true,
  click = true,
  hide = true,
  scale = true,
  title = true,
  accTitle = true,
  accDescr = true,
}

local KINDS = { choice = "choice", fork = "bar", join = "bar" }
local DIRECTIONS = { TD = "TD", TB = "TD", LR = "LR", RL = "RL", BT = "BT" }

local function fail(lnum, msg)
  error(("line %d: %s"):format(lnum, msg), 0)
end

local function scope(st)
  local top = st.stack[#st.stack]
  return top and top.sg
end

local function ensure(st, id, label, shape)
  local g = st.g
  if g.sub_by_id[id] then
    return
  end
  if not g.by_id[id] then
    model.add_node(g, id, label or id, shape or "round")
    local sg = scope(st)
    if sg then
      sg.nodes[#sg.nodes + 1] = id
    end
  else
    model.add_node(g, id, label, shape)
  end
end

-- `[*]` resolved to this scope's start or end node.
local function endpoint(st, ref, as_end)
  if ref ~= syntax.START_END then
    ensure(st, ref)
    return ref
  end
  local sg = scope(st)
  local kind = as_end and "end" or "start"
  local id = kind .. ":" .. (sg and sg.id or "root")
  ensure(st, id, "", kind)
  return id
end

local function add_transition(st, from, to, label)
  from = endpoint(st, from, false)
  to = endpoint(st, to, true)
  model.add_edge(st.g, from, to, { label = label })
end

local function add_note(st, target, text)
  ensure(st, target)
  st.notes = st.notes + 1
  local id = "note:" .. st.notes
  ensure(st, id, syntax.text(text), "record")
  model.add_edge(
    st.g,
    target,
    id,
    { style = "dotted", head = "none", head_kind = "none", tail_kind = "none" }
  )
end

-- A node of this id declared earlier (by a transition) is replaced by the
-- composite: edges keep pointing at the id, which is now a subgraph.
local function drop_node(g, id)
  local n = g.by_id[id]
  g.by_id[id] = nil
  for i, x in ipairs(g.nodes) do
    if x == n then
      table.remove(g.nodes, i)
      break
    end
  end
  for _, sg in ipairs(g.subgraphs) do
    sg.nodes = vim.tbl_filter(function(m)
      return m ~= id
    end, sg.nodes)
  end
end

local function open_composite(st, d, lnum)
  local g = st.g
  if g.sub_by_id[d.id] then
    fail(lnum, "duplicate state " .. d.id)
  end
  local label = d.label or (g.by_id[d.id] and g.by_id[d.id].label) or d.id
  if g.by_id[d.id] then
    drop_node(g, d.id)
  end
  local parent = scope(st)
  local sg = model.add_subgraph(g, d.id, label, parent and parent.id)
  st.stack[#st.stack + 1] = { sg = sg, line = lnum }
end

local function index_of(list, item)
  for i, x in ipairs(list) do
    if x == item then
      return i
    end
  end
end

-- First `--` of a composite: its content so far becomes region 1.
local function first_region(st, comp)
  local g = st.g
  local r1 = model.add_subgraph(g, comp.id .. "--1", "", comp.id)
  table.remove(g.subgraphs)
  table.insert(g.subgraphs, index_of(g.subgraphs, comp) + 1, r1)
  r1.nodes, comp.nodes = comp.nodes, {}
  for _, id in ipairs(comp.children) do
    if id ~= r1.id then
      g.sub_by_id[id].parent = r1.id
      r1.children[#r1.children + 1] = id
    end
  end
  comp.children = { r1.id }
  return r1
end

local function add_region(st, lnum)
  local top = st.stack[#st.stack]
  if not top then
    fail(lnum, "-- outside a composite state")
  end
  local comp = top.region and st.stack[#st.stack - 1].sg or top.sg
  if not top.region then
    first_region(st, comp)
  else
    st.stack[#st.stack] = nil
  end
  local g = st.g
  local sg = model.add_subgraph(g, ("%s--%d"):format(comp.id, #comp.children + 1), "", comp.id)
  st.stack[#st.stack + 1] = { sg = sg, line = lnum, region = true }
end

local function close_composite(st, lnum)
  local top = st.stack[#st.stack]
  if not top then
    fail(lnum, "} without composite state")
  end
  if top.region then
    st.stack[#st.stack] = nil
  end
  st.stack[#st.stack] = nil
end

local function parse_state(st, rest, lnum)
  local d = syntax.declaration(rest)
  if not d then
    fail(lnum, "syntax error: state " .. rest)
  end
  if d.open then
    return open_composite(st, d, lnum)
  end
  local shape = "round"
  if d.kind then
    shape = KINDS[d.kind] or fail(lnum, "unknown state type <<" .. d.kind .. ">>")
  end
  ensure(st, d.id, d.kind and "" or d.label, shape)
end

local function parse_note(st, stmt, lnum)
  local target, text = syntax.note(stmt)
  if not target then
    fail(lnum, "syntax error: " .. stmt)
  end
  if text then
    return add_note(st, target, text)
  end
  st.block = { target = target, line = lnum, text = {} }
end

local function add_description(st, id, text)
  ensure(st, id)
  local d = st.desc[id] or {}
  st.desc[id] = d
  d[#d + 1] = text
end

local function set_direction(st, dir, lnum)
  local sg = scope(st)
  local value = DIRECTIONS[dir] or fail(lnum, "unknown direction " .. dir)
  if sg then
    sg.direction = value
  else
    st.g.direction = value
  end
end

-- Statements starting with a keyword; true when `stmt` was handled.
local function parse_keyword(st, stmt, word, lnum)
  local dir = stmt:match("^direction%s+(%a+)$")
  if dir then
    set_direction(st, dir, lnum)
    return true
  end
  local rest = stmt:match("^state%s+(.+)$")
  if rest then
    parse_state(st, rest, lnum)
    return true
  end
  if stmt == "}" then
    close_composite(st, lnum)
    return true
  end
  if stmt == "--" then
    add_region(st, lnum)
    return true
  end
  if word == "note" then
    parse_note(st, stmt, lnum)
    return true
  end
  return false
end

local function parse_statement(st, stmt, lnum)
  local word = stmt:match("^(%a+)")
  if IGNORED[word] or parse_keyword(st, stmt, word, lnum) then
    return
  end
  local from, to, label = syntax.transition(stmt)
  if from then
    return add_transition(st, from, to, label)
  end
  if stmt:match("^[%w_%.]+$") then
    return ensure(st, stmt)
  end
  local id, text = stmt:match("^([%w_%.]+)%s*:%s*(.+)$")
  if not id then
    fail(lnum, "syntax error: " .. stmt)
  end
  add_description(st, id, text)
end

local function parse_line(st, stmt, lnum)
  if not st.g then
    if stmt ~= "stateDiagram" and stmt ~= "stateDiagram-v2" then
      fail(lnum, "expected stateDiagram")
    end
    st.g = model.new("TD")
  elseif st.block then
    if stmt:match("^end%s+note$") then
      add_note(st, st.block.target, table.concat(st.block.text, "\n"))
      st.block = nil
    else
      st.block.text[#st.block.text + 1] = stmt
    end
  else
    parse_statement(st, stmt, lnum)
  end
end

local function build_rows(st)
  for id, lines in pairs(st.desc) do
    local n = st.g.by_id[id]
    if n then
      n.rows = { lines }
    end
  end
end

-- Parse the source into a Graph; raises a plain string on a syntax error.
---@param lines string[]
---@return table graph
function M.parse(lines)
  local st = { notes = 0, stack = {}, desc = {} }
  for i = source.first_content(lines), #lines do
    local stmt = lines[i]:match("^%s*(.-)%s*$")
    if stmt ~= "" and not stmt:match("^%%%%") then
      parse_line(st, stmt, i)
    end
  end
  if st.block then
    fail(st.block.line, "note is not closed")
  end
  local open = st.stack[1]
  if open then
    fail(open.line, ("state %s is not closed"):format(open.sg.id))
  end
  st.g = st.g or model.new()
  build_rows(st)
  return st.g
end

---@param lines string[]
---@param ctx { width: integer, charset?: string, compact?: boolean }
---@return doc_preview.Output
function M.render(lines, ctx)
  local g = M.parse(lines)
  if #g.nodes == 0 then
    error("no nodes", 0)
  end
  return fit.render(g, lines, ctx)
end

return M
