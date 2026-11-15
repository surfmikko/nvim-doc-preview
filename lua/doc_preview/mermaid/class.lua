-- Mermaid class diagram: parse to graph.model with record nodes (syntax
-- tokens in class_syntax.lua). Parse result: a Graph plus `g.classes[id] =
-- { annotation?, members = {}, methods = {} }`; node.rows holds the non-empty
-- sections in the order annotation, members, methods.
-- Namespaces become clusters (graph subgraphs), not name prefixes: members
-- stay visible as classes and edges may cross the border. Notes are record
-- nodes (id `note:N`) joined to their class by a dotted edge without ends.
-- render() draws through the shared width policy (fit.lua).
local fit = require("doc_preview.mermaid.fit")
local model = require("doc_preview.graph.model")
local source = require("doc_preview.mermaid.source")
local syntax = require("doc_preview.mermaid.class_syntax")

local M = {}

-- Styling and link statements: accepted and ignored.
local IGNORED = {
  classDef = true,
  cssClass = true,
  style = true,
  click = true,
  link = true,
  callback = true,
  accTitle = true,
  accDescr = true,
}

local DIRECTIONS = { TD = "TD", TB = "TD", LR = "LR", RL = "RL", BT = "BT" }

local function fail(lnum, msg)
  error(("line %d: %s"):format(lnum, msg), 0)
end

local function parse_header(stmt, lnum)
  if stmt ~= "classDiagram" and stmt ~= "classDiagram-v2" then
    fail(lnum, "expected classDiagram")
  end
  return model.new("TD")
end

-- The class `id`, created on first mention (inside a namespace it joins it).
local function ensure(st, id, label)
  local g = st.g
  if not g.by_id[id] then
    model.add_node(g, id, label, "record")
    st.g.classes[id] = { members = {}, methods = {} }
    if st.ns then
      st.ns.nodes[#st.ns.nodes + 1] = id
    end
  elseif label and label ~= id then
    g.by_id[id].label = label
  end
  return st.g.classes[id]
end

local function add_member(st, id, text)
  local c = ensure(st, id)
  text = text:match("^%s*(.-)%s*$")
  if text == "" then
    return
  end
  local note = text:match("^<<(.-)>>$")
  if note then
    c.annotation = note
  elseif text:find("(", 1, true) then
    c.methods[#c.methods + 1] = syntax.generics(text)
  else
    c.members[#c.members + 1] = syntax.generics(text)
  end
end

local function add_relation(st, r)
  ensure(st, r.from, r.from_label)
  ensure(st, r.to, r.to_label)
  model.add_edge(st.g, r.from, r.to, {
    style = r.style,
    head = r.head_kind == "arrow" and "arrow" or "none",
    tail = r.tail_kind == "arrow" and "arrow" or "none",
    head_kind = r.head_kind,
    tail_kind = r.tail_kind,
    head_label = r.head_card,
    tail_label = r.tail_card,
    label = r.label,
  })
end

local function add_note(st, target, text)
  if target then
    ensure(st, target)
  end
  st.notes = st.notes + 1
  local id = "note:" .. st.notes
  local label = text:gsub("\\n", "\n"):gsub("<br%s*/?>", "\n")
  model.add_node(st.g, id, label, "record")
  if target then
    model.add_edge(
      st.g,
      target,
      id,
      { style = "dotted", head = "none", head_kind = "none", tail_kind = "none" }
    )
  end
end

-- `class Name`, `class Name["label"]`, `class Name {`. Returns true when a
-- body is opened.
local function parse_class(st, rest, lnum)
  local id, label, pos = syntax.name(rest, 1)
  if not id then
    fail(lnum, "syntax error: class " .. rest)
  end
  local tail = rest:sub(pos):match("^%s*(.-)%s*$")
  local alias = tail:match('^%[%s*"?(.-)"?%s*%]$')
  if alias then
    label, tail = alias, ""
  end
  ensure(st, id, label)
  if tail == "{" then
    st.body = { id = id, line = lnum }
  elseif tail ~= "" then
    fail(lnum, "syntax error: class " .. rest)
  end
end

local function parse_namespace(st, rest, lnum)
  local id = rest:match("^(%S+)%s*{$")
  if not id or st.ns then
    fail(lnum, st.ns and "namespace inside namespace" or "syntax error: namespace " .. rest)
  end
  st.ns = model.add_subgraph(st.g, id, id)
  st.ns_line = lnum
end

local function parse_note(st, stmt, lnum)
  local target, text = stmt:match('^note%s+for%s+(%S+)%s+"(.*)"$')
  if target then
    local id = syntax.name(target, 1)
    add_note(st, id or target, text)
    return true
  end
  text = stmt:match('^note%s+"(.*)"$')
  if text then
    add_note(st, nil, text)
    return true
  end
  fail(lnum, "syntax error: " .. stmt)
end

-- Statements starting with a keyword; true when `stmt` was handled.
local function parse_keyword(st, stmt, word, lnum)
  local dir = stmt:match("^direction%s+(%a+)$")
  if dir then
    st.g.direction = DIRECTIONS[dir] or fail(lnum, "unknown direction " .. dir)
    return true
  end
  local rest = stmt:match("^class%s+(.+)$")
  if rest then
    parse_class(st, rest, lnum)
    return true
  end
  rest = stmt:match("^namespace%s+(.+)$")
  if rest then
    parse_namespace(st, rest, lnum)
    return true
  end
  if stmt == "}" then
    if not st.ns then
      fail(lnum, "} without namespace or class body")
    end
    st.ns, st.ns_line = nil, nil
    return true
  end
  if word == "note" then
    parse_note(st, stmt, lnum)
    return true
  end
  return false
end

-- `Name : member`
local function parse_member(st, stmt, lnum)
  local id, _, pos = syntax.name(stmt, 1)
  local member = id and stmt:sub(pos):match("^%s*:%s*(.+)$")
  if not member then
    fail(lnum, "syntax error: " .. stmt)
  end
  add_member(st, id, member)
end

local function parse_statement(st, stmt, lnum)
  local word = stmt:match("^(%a+)")
  if IGNORED[word] or parse_keyword(st, stmt, word, lnum) then
    return
  end
  local ann, target = stmt:match("^(<<.->>)%s+(.+)$")
  if ann then
    local id = syntax.name(target, 1) or fail(lnum, "syntax error: " .. stmt)
    return add_member(st, id, ann)
  end
  local r = syntax.relation(stmt)
  if r then
    return add_relation(st, r)
  end
  parse_member(st, stmt, lnum)
end

local function build_rows(g)
  for _, n in ipairs(g.nodes) do
    local c = g.classes[n.id]
    if c then
      local rows = {}
      for _, sec in ipairs({
        { c.annotation and ("<<" .. c.annotation .. ">>") },
        c.members,
        c.methods,
      }) do
        if #sec > 0 then
          rows[#rows + 1] = sec
        end
      end
      n.rows = #rows > 0 and rows or nil
    end
  end
end

local function parse_line(st, stmt, lnum)
  if not st.g then
    st.g = parse_header(stmt, lnum)
    st.g.classes = {}
  elseif st.body then
    if stmt == "}" then
      st.body = nil
    else
      add_member(st, st.body.id, stmt)
    end
  else
    parse_statement(st, stmt, lnum)
  end
end

local function check_closed(st)
  if st.body then
    fail(st.body.line, ("class %s is not closed"):format(st.body.id))
  end
  if st.ns then
    fail(st.ns_line, ("namespace %s is not closed"):format(st.ns.id))
  end
end

-- Parse the source into a Graph; raises a plain string on a syntax error.
---@param lines string[]
---@return table graph
function M.parse(lines)
  local st = { notes = 0 }
  for i = source.first_content(lines), #lines do
    local stmt = lines[i]:match("^%s*(.-)%s*$")
    if stmt ~= "" and not stmt:match("^%%%%") then
      parse_line(st, stmt, i)
    end
  end
  check_closed(st)
  local g = st.g or model.new()
  g.classes = g.classes or {}
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
  return fit.render(g, lines, ctx)
end

return M
