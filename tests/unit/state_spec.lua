local text = require("doc_preview.core.text")
local mermaid = require("doc_preview.mermaid")
local model = require("doc_preview.graph.model")
local state = require("doc_preview.mermaid.state")
local syntax = require("doc_preview.mermaid.state_syntax")

local function parse(...)
  return state.parse({ "stateDiagram-v2", ... })
end

local function fails(msg, ...)
  local args = { ... }
  assert.has_error(function()
    parse(unpack(args))
  end, msg)
end

describe("state.parse", function()
  it("reads header variants and direction", function()
    assert.equals("TD", state.parse({ "stateDiagram" }).direction)
    assert.equals("LR", parse("direction LR").direction)
    assert.equals("TD", parse("direction TB").direction)
    assert.has_error(function()
      state.parse({ "graph TD" })
    end, "line 1: expected stateDiagram")
    fails("line 2: unknown direction XX", "direction XX")
  end)

  it("makes states round nodes by first mention and keeps the graph valid", function()
    local g = parse("A --> B", "B --> C : go")
    assert.is_true(model.validate(g))
    assert.equals("round", g.by_id.A.shape)
    assert.equals(3, #g.nodes)
    assert.equals("go", g.edges[2].label)
    assert.equals("arrow", g.edges[1].head)
  end)

  it("accepts transitions without spaces and css suffixes", function()
    local g = parse("A-->B:go", "B:::hot --> C:::hot : x")
    assert.equals("go", g.edges[1].label)
    assert.equals("C", g.edges[2].to)
    assert.equals("x", g.edges[2].label)
  end)

  it("gives each scope its own start and end", function()
    local g = parse("[*] --> A", "A --> [*]", "state X {", "[*] --> b", "b --> [*]", "}")
    assert.equals("start", g.by_id["start:root"].shape)
    assert.equals("end", g.by_id["end:root"].shape)
    assert.equals("start", g.by_id["start:X"].shape)
    assert.equals("end", g.by_id["end:X"].shape)
    assert.same({ "start:X", "b", "end:X" }, g.sub_by_id.X.nodes)
    assert.equals("start:X", g.edges[3].from)
  end)

  it("uses `[*]` as start for a source and end for a target", function()
    local g = parse("[*] --> [*]")
    assert.equals("start:root", g.edges[1].from)
    assert.equals("end:root", g.edges[1].to)
  end)

  it('reads `state "Long" as id` and description lines into rows', function()
    local g = parse('state "Long name" as s1', "s1 : one", "s1 : two", "s2 : solo")
    assert.equals("Long name", g.by_id.s1.label)
    assert.same({ { "one", "two" } }, g.by_id.s1.rows)
    assert.same({ { "solo" } }, g.by_id.s2.rows)
    assert.is_true(model.validate(g))
  end)

  it("maps choice, fork and join to shapes", function()
    local g = parse("state c <<choice>>", "state f <<fork>>", "state j <<join>>")
    assert.equals("choice", g.by_id.c.shape)
    assert.equals("bar", g.by_id.f.shape)
    assert.equals("bar", g.by_id.j.shape)
    assert.equals("", g.by_id.c.label)
    fails("line 2: unknown state type <<weird>>", "state c <<weird>>")
  end)

  it("nests composites as subgraphs with their own direction", function()
    local g = parse("state A {", "direction LR", "state B {", "x --> y", "}", "z", "}", "A --> w")
    assert.is_true(model.validate(g))
    assert.equals("A", g.sub_by_id.B.parent)
    assert.same({ "B" }, g.sub_by_id.A.children)
    assert.same({ "z" }, g.sub_by_id.A.nodes)
    assert.equals("LR", g.sub_by_id.A.direction)
    assert.equals("TD", g.direction)
    assert.is_nil(g.by_id.A)
  end)

  it("turns an earlier plain state into the composite", function()
    local g = parse("a --> Box", 'state "Title" as Box {', "x", "}")
    assert.is_nil(g.by_id.Box)
    assert.equals("Title", g.sub_by_id.Box.title)
    assert.is_true(model.validate(g))
    fails("line 4: duplicate state Box", "state Box {", "}", "state Box {")
  end)

  it("splits concurrent regions into unnamed clusters", function()
    local g = parse("state S {", "a --> b", "--", "c --> d", "state In {", "e", "}", "}")
    assert.is_true(model.validate(g))
    assert.same({ "S--1", "S--2" }, g.sub_by_id.S.children)
    assert.same({ "a", "b" }, g.sub_by_id["S--1"].nodes)
    assert.same({ "c", "d" }, g.sub_by_id["S--2"].nodes)
    assert.equals("", g.sub_by_id["S--2"].title)
    assert.equals("S--2", g.sub_by_id.In.parent)
    assert.same({}, g.sub_by_id.S.nodes)
  end)

  it("reparents composites declared before the first `--`", function()
    local g = parse("state S {", "state In {", "e", "}", "--", "f", "}")
    assert.equals("S--1", g.sub_by_id.In.parent)
    assert.same({ "In" }, g.sub_by_id["S--1"].children)
    assert.is_true(model.validate(g))
  end)

  it("makes notes dotted-edge record nodes", function()
    local g = parse("A", "note right of A : hi\\nthere", "note left of A", "l1", "l2", "end note")
    assert.is_true(model.validate(g))
    assert.equals("record", g.by_id["note:1"].shape)
    assert.equals("hi\nthere", g.by_id["note:1"].label)
    assert.equals("l1\nl2", g.by_id["note:2"].label)
    assert.equals("dotted", g.edges[1].style)
    assert.equals("none", g.edges[1].head)
  end)

  it("ignores styling statements", function()
    local g = parse(
      "classDef a fill:#f00",
      "A --> B",
      "class A a",
      "style B fill:#0f0",
      "hide empty description"
    )
    assert.equals(2, #g.nodes)
    assert.equals(1, #g.edges)
  end)

  it("names the line of syntax errors", function()
    fails("line 3: syntax error: nonsense here", "A --> B", "nonsense here")
    fails("line 3: } without composite state", "A", "}")
    fails("line 2: state X is not closed", "state X {", "a")
    fails("line 3: note is not closed", "A", "note right of A", "text")
    fails("line 2: -- outside a composite state", "--")
    fails("line 2: syntax error: note near A", "note near A")
  end)

  it("never throws anything but a string on garbage", function()
    local junk =
      { "}", "{", "state", "state {", "--> -->", "[*]", "note", ":", "state X <<", "A -->", '"' }
    for _, l in ipairs(junk) do
      local ok, err = pcall(parse, l)
      assert.is_true(ok or type(err) == "string")
    end
  end)
end)

describe("state_syntax", function()
  it("parses references and transitions", function()
    assert.equals("[*]", syntax.ref(" [*] "))
    assert.is_nil(syntax.ref("two words"))
    assert.same({ "A", "B", "x" }, { syntax.transition("A --> B : x") })
    assert.is_nil(syntax.transition("A -> B"))
  end)

  it("parses declarations", function()
    assert.same({ id = "s", label = "L", open = true }, syntax.declaration('"L" as s {'))
    assert.same({ id = "c", kind = "choice", open = false }, syntax.declaration("c <<choice>>"))
    assert.is_nil(syntax.declaration("[*]"))
  end)
end)

local function render(body, width, charset)
  local lines = { "stateDiagram-v2" }
  vim.list_extend(lines, body)
  local o = mermaid.render(lines, { width = width or 60, charset = charset })
  return o.lines, table.concat(o.lines, "\n")
end

local function assert_fits(lines, width)
  for _, l in ipairs(lines) do
    assert.is_true(text.width(l) <= width, l)
  end
end

describe("state render", function()
  it("is registered for both type names", function()
    for _, head in ipairs({ "stateDiagram", "stateDiagram-v2" }) do
      local o = mermaid.render({ head, "A --> B" }, { width = 60 })
      assert.matches("│ A │", table.concat(o.lines, "\n"))
    end
  end)

  it("reports syntax errors with the line", function()
    local o = mermaid.render({ "stateDiagram-v2", "A --> B", "oops oops" }, { width = 60 })
    assert.matches("line 3: syntax error", table.concat(o.lines, "\n"))
  end)

  it("draws start and end markers around a lifecycle with a cycle", function()
    local lines, all =
      render({ "[*] --> Idle", "Idle --> Run : go", "Run --> Idle", "Run --> [*]" })
    assert.equals("●", vim.trim(lines[1]))
    assert.equals("◉", vim.trim(lines[#lines]))
    assert.matches("go", all)
    assert_fits(lines, 60)
  end)

  it("draws a self transition", function()
    local _, all = render({ "A --> A : tick" })
    assert.matches("tick", all)
  end)

  it("uses the ascii markers", function()
    local lines = render({ "[*] --> A", "A --> [*]" }, 40, "ascii")
    assert.equals("(*)", vim.trim(lines[1]))
    assert.equals("(@)", vim.trim(lines[#lines]))
  end)

  it("draws a composite with its own start and end inside", function()
    local lines, all = render({ "state A {", "[*] --> B", "B --> [*]", "}", "[*] --> A" })
    assert.matches("┌─ A ", lines[1] .. all)
    local _, n = all:gsub("●", "")
    assert.equals(2, n)
    _, n = all:gsub("◉", "")
    assert.equals(1, n)
    assert_fits(lines, 60)
  end)

  it("draws a choice without label and fork bars by direction", function()
    local _, all = render({ "state c <<choice>>", "A --> c", "c --> B", "c --> C" })
    assert.matches("<   >", all)
    _, all = render({ "state f <<fork>>", "[*] --> f", "f --> A", "f --> B", "f --> C" })
    assert.matches("━━━━━━━", all)
    _, all =
      render({ "direction LR", "state j <<join>>", "A --> j", "B --> j", "C --> j", "j --> D" }, 70)
    assert.matches("┃", all)
    assert.is_nil(all:find("━━━━", 1, true))
  end)

  it("draws notes with a dotted edge", function()
    local _, all = render({ "A --> B", "note right of B : hello" })
    assert.matches("hello", all)
    assert.matches("┆", all)
  end)

  it("falls back to top-down, then to the boxed source", function()
    local body = { "direction LR", "A --> B : a long label", "B --> C" }
    local lines = render(body, 24)
    assert_fits(lines, 24)
    assert.is_nil(table.concat(lines):find("▶", 1, true))
    lines = render(body, 8)
    assert_fits(lines, 8)
  end)
end)

describe("graph.shapes state markers", function()
  local shapes = require("doc_preview.graph.shapes")
  it("sizes them for the layout", function()
    assert.same({ 3, 1 }, { shapes.size({ id = "s", label = "", shape = "start" }) })
    assert.same({ 7, 1 }, { shapes.size({ id = "b", label = "", shape = "bar" }) })
    assert.same({ 1, 3 }, { shapes.size({ id = "b", label = "", shape = "bar" }, true) })
    assert.same({ 5, 3 }, { shapes.size({ id = "c", label = "", shape = "choice" }) })
  end)
end)
