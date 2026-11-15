-- Mermaid ER diagram: parse to graph.model with record nodes (tokens in
-- er_syntax.lua). Parse result: a Graph plus `g.entities[id] = { attrs }`
-- with attrs `{ type, name, keys, comment? }`; node.rows holds one section of
-- aligned `type name keys "comment"` columns (none for an entity without
-- attributes). Edges carry cardinality kinds in tail_kind (first entity) and
-- head_kind (second), `style` solid for identifying and dotted for
-- non-identifying relationships, and `identifying`.
-- render() draws through the shared width policy (fit.lua); `g.end_room = 2`
-- asks the layout for gaps that hold the two-cell cardinality ends.
local fit = require("doc_preview.mermaid.fit")
local model = require("doc_preview.graph.model")
local source = require("doc_preview.mermaid.source")
local syntax = require("doc_preview.mermaid.er_syntax")
local text = require("doc_preview.core.text")

local M = {}

-- Styling statements: accepted and ignored.
local IGNORED = { classDef = true, style = true, class = true, accTitle = true, accDescr = true }

local DIRECTIONS = { TD = "TD", TB = "TD", LR = "LR", RL = "RL", BT = "BT" }

local function fail(lnum, msg)
  error(("line %d: %s"):format(lnum, msg), 0)
end

-- The entity `id`, created on first mention; `label` is an alias.
local function ensure(g, id, label)
  if not g.by_id[id] then
    model.add_node(g, id, label, "record")
    g.entities[id] = { attrs = {} }
  elseif label then
    g.by_id[id].label = label
  end
  return g.entities[id]
end

-- `NAME`, `NAME["Alias"]`, `NAME[Alias]` optionally followed by `{`
-- (`{}` is an empty body). Returns id, body opened, or nil.
local function entity_header(g, stmt)
  local id, pos = syntax.name(stmt, 1)
  if not id then
    return nil
  end
  local rest = stmt:sub(pos):match("^%s*(.-)%s*$")
  local alias, tail = rest:match('^%[%s*"?(.-)"?%s*%]%s*(.*)$')
  if not alias then
    tail = rest
  end
  if tail ~= "" and tail ~= "{" and tail ~= "{}" then
    return nil
  end
  ensure(g, id, alias ~= "" and alias or nil)
  return id, tail == "{"
end

local function column_text(a)
  local cols =
    { a.type, a.name, table.concat(a.keys, ","), a.comment and ('"' .. a.comment .. '"') or "" }
  return cols
end

-- Pad each column to its widest cell (display width); trailing blanks cut.
local function build_rows(g)
  for _, n in ipairs(g.nodes) do
    local attrs = g.entities[n.id].attrs
    if #attrs > 0 then
      local cells, widths = {}, { 0, 0, 0, 0 }
      for i, a in ipairs(attrs) do
        cells[i] = column_text(a)
        for c = 1, 4 do
          widths[c] = math.max(widths[c], text.width(cells[i][c]))
        end
      end
      local section = {}
      for i, row in ipairs(cells) do
        for c = 1, 3 do
          row[c] = text.pad(row[c], widths[c])
        end
        section[i] = table.concat(row, " "):gsub("%s+$", "")
      end
      n.rows = { section }
    end
  end
end

local function add_relation(g, r)
  ensure(g, r.from)
  ensure(g, r.to)
  local e = model.add_edge(g, r.from, r.to, {
    style = r.identifying and "solid" or "dotted",
    head = "none",
    tail = "none",
    head_kind = r.head_kind,
    tail_kind = r.tail_kind,
    label = r.label,
  })
  e.identifying = r.identifying
end

local function parse_statement(st, stmt, lnum)
  local g = st.g
  if IGNORED[stmt:match("^(%a+)")] then
    return
  end
  local dir = stmt:match("^direction%s+(%a+)$")
  if dir then
    g.direction = DIRECTIONS[dir] or fail(lnum, "unknown direction " .. dir)
    return
  end
  local r = syntax.relation(stmt)
  if r then
    return add_relation(g, r)
  end
  local id, body = entity_header(g, stmt)
  if not id then
    fail(lnum, "syntax error: " .. stmt)
  end
  if body then
    st.body = { id = id, line = lnum }
  end
end

local function parse_attribute(st, stmt, lnum)
  local a = syntax.attribute(stmt)
  if not a then
    fail(lnum, "syntax error: " .. stmt)
  end
  local attrs = st.g.entities[st.body.id].attrs
  attrs[#attrs + 1] = a
end

local function parse_line(st, stmt, lnum)
  if not st.g then
    if stmt ~= "erDiagram" then
      fail(lnum, "expected erDiagram")
    end
    st.g = model.new("TD")
    st.g.entities = {}
  elseif st.body then
    if stmt == "}" then
      st.body = nil
    else
      parse_attribute(st, stmt, lnum)
    end
  else
    parse_statement(st, stmt, lnum)
  end
end

-- Parse the source into a Graph; raises a plain string on a syntax error.
---@param lines string[]
---@return table graph
function M.parse(lines)
  local st = {}
  for i = source.first_content(lines), #lines do
    local stmt = lines[i]:match("^%s*(.-)%s*$")
    if stmt ~= "" and not stmt:match("^%%%%") then
      parse_line(st, stmt, i)
    end
  end
  if st.body then
    fail(st.body.line, ("entity %s is not closed"):format(st.body.id))
  end
  local g = st.g or model.new()
  g.entities = g.entities or {}
  build_rows(g)
  return g
end

---@param lines string[]
---@param ctx { width: integer, charset?: string, compact?: boolean }
---@return doc_preview.Output
function M.render(lines, ctx)
  local g = M.parse(lines)
  if #g.nodes == 0 then
    error("no nodes", 0)
  end
  g.end_room = 2
  return fit.render(g, lines, ctx)
end

return M
