local er = require("doc_preview.mermaid.er")
local mermaid = require("doc_preview.mermaid")
local model = require("doc_preview.graph.model")
local syntax = require("doc_preview.mermaid.er_syntax")
local text = require("doc_preview.core.text")

local function parse(...)
  return er.parse({ "erDiagram", ... })
end

local function fails(msg, ...)
  local args = { ... }
  assert.has_error(function()
    parse(unpack(args))
  end, msg)
end

describe("er.parse", function()
  it("reads the header and direction", function()
    assert.equals("TD", er.parse({ "erDiagram" }).direction)
    assert.equals("LR", parse("direction LR").direction)
    assert.equals("TD", parse("direction TB").direction)
    assert.has_error(function()
      er.parse({ "graph TD" })
    end, "line 1: expected erDiagram")
    fails("line 2: unknown direction XX", "direction XX")
  end)

  it("creates entities from relationships with kinds and style", function()
    local g = parse("A ||--o{ B : places")
    assert.is_true(model.validate(g))
    assert.equals("record", g.by_id.B.shape)
    local e = g.edges[1]
    assert.equals("one", e.tail_kind)
    assert.equals("zero_many", e.head_kind)
    assert.equals("solid", e.style)
    assert.is_true(e.identifying)
    assert.equals("places", e.label)
  end)

  it("maps every symbol on both sides", function()
    local left = { ["||"] = "one", ["|o"] = "zero_one", ["}o"] = "zero_many", ["}|"] = "one_many" }
    local right = { ["||"] = "one", ["o|"] = "zero_one", ["o{"] = "zero_many", ["|{"] = "one_many" }
    for l, lk in pairs(left) do
      for r, rk in pairs(right) do
        local rel = syntax.relation("A " .. l .. "--" .. r .. " B : x")
        assert.equals(lk, rel.tail_kind)
        assert.equals(rk, rel.head_kind)
      end
    end
  end)

  it("treats .. as non-identifying", function()
    local e = parse("A ||..|| B : x").edges[1]
    assert.equals("dotted", e.style)
    assert.is_false(e.identifying)
  end)

  it("accepts word forms and `optionally to`", function()
    local e = parse("A one or zero to many(1) B : x", "A only one optionally to 0+ B").edges
    assert.equals("zero_one", e[1].tail_kind)
    assert.equals("one_many", e[1].head_kind)
    assert.is_true(e[1].identifying)
    assert.equals("one", e[2].tail_kind)
    assert.equals("zero_many", e[2].head_kind)
    assert.is_false(e[2].identifying)
  end)

  it("reads quoted and bare labels, or none", function()
    local e = parse("A ||--|| B : bare words", 'A ||--|| B : "quoted"', "A ||--|| B").edges
    assert.equals("bare words", e[1].label)
    assert.equals("quoted", e[2].label)
    assert.is_nil(e[3].label)
  end)

  it("reads attributes with keys and comments into aligned rows", function()
    local g =
      parse("CUSTOMER {", "  string name PK", '  int id PK, FK "surrogate"', "  date born", "}")
    assert.same(
      { type = "int", name = "id", keys = { "PK", "FK" }, comment = "surrogate" },
      g.entities.CUSTOMER.attrs[2]
    )
    assert.same({
      {
        "string name PK",
        'int    id   PK,FK "surrogate"',
        "date   born",
      },
    }, g.by_id.CUSTOMER.rows)
  end)

  it("aligns columns by display width", function()
    local g = parse("A {", "  日本 x", "  ab yy", "}")
    local rows = g.by_id.A.rows[1]
    assert.equals("日本 x", rows[1])
    assert.equals("ab   yy", rows[2])
  end)

  it("leaves rows nil for entities without attributes", function()
    local g = parse("A {", "}", "B {}", "C")
    assert.is_nil(g.by_id.A.rows)
    assert.is_nil(g.by_id.B.rows)
    assert.equals(3, #g.nodes)
  end)

  it("reads aliases and quoted names", function()
    local g = parse('p["Person"] {', "  int id", "}", "car[Car]", '"two words" ||--o{ p : x')
    assert.equals("Person", g.by_id.p.label)
    assert.equals("Car", g.by_id.car.label)
    assert.is_truthy(g.by_id["two words"])
  end)

  it("ignores styling statements and comments", function()
    local g =
      parse("%% c", "A ||--o{ B : x", "classDef big fill:#f00", "class A big", "style B fill:#0f0")
    assert.equals(2, #g.nodes)
  end)

  it("names the line of a syntax error", function()
    fails("line 3: syntax error: A ||--", "A ||--o{ B : x", "A ||--")
    fails("line 4: syntax error: justone", "A {", "  int id", "  justone", "}")
    fails("line 2: entity A is not closed", "A {", "  int id")
  end)

  it("never throws anything but a string on garbage", function()
    local garbage =
      { "}", "{", "A {", "||--o{", '"', "A ||--o{", "A ||--o{ B C", "[*]", "A[", "1+ to 1+", "\t" }
    for _, line in ipairs(garbage) do
      local ok, err = pcall(parse, line)
      assert.is_true(ok or type(err) == "string")
    end
  end)
end)

local function draw(width, charset, ...)
  local o = er.render({ "erDiagram", ... }, { width = width, charset = charset })
  return o.lines
end

local function joined(lines)
  return table.concat(lines, "\n")
end

describe("er drawing", function()
  -- The two cells above/below the boxes of `A <tail>--<head> B` (TD), top to bottom.
  local function column(rel, charset)
    local lines = draw(60, charset, "A " .. rel .. " B")
    local out = {}
    for i = 4, #lines - 3 do
      out[#out + 1] = vim.trim(lines[i])
    end
    return out
  end

  it("draws the ends of every cardinality on TD, unicode", function()
    assert.same({ "╪", "╪", "│", "o", "┴" }, column("||--o{"))
    assert.same({ "┬", "╪", "│", "o", "╪" }, column("}|--o|"))
    assert.same({ "╪", "o", "│", "╪", "╪" }, column("|o--||"))
    assert.same({ "┬", "o", "│", "╪", "┴" }, column("}o--|{"))
  end)

  it("draws ascii fallbacks on TD", function()
    assert.same({ "+", "+", "|", "o", "^" }, column("||--o{", "ascii"))
    assert.same({ "v", "+", "|", "o", "+" }, column("}|--o|", "ascii"))
    assert.same({ "v", "o", ":", "+", "^" }, column("}o..|{", "ascii"))
  end)

  it("draws the ends on LR with the crow's foot facing the entity", function()
    assert.is_truthy(joined(draw(80, "unicode", "direction LR", "A }o--|{ B")):find("├o.-╫┤"))
    assert.is_truthy(joined(draw(80, "ascii", "direction LR", "A }o--|{ B")):find(">o.-%+<"))
    assert.is_truthy(joined(draw(80, "unicode", "direction LR", "A ||--o| B")):find("╫╫.-o╫"))
  end)

  it("draws a dotted line for non-identifying and solid for identifying", function()
    assert.is_truthy(joined(draw(60, "unicode", "A ||..o{ B : x")):find("┆", 1, true))
    assert.is_nil(joined(draw(60, "unicode", "A ||--o{ B : x")):find("┆", 1, true))
  end)

  it("shows the relationship label beside the line", function()
    assert.is_truthy(joined(draw(60, "unicode", "A ||--o{ B : places")):find("places", 1, true))
  end)

  it("aligns attributes by display width and handles entities without attributes", function()
    local lines = draw(60, "unicode", "A {", "  日本 id PK", "  int n", "}", "A ||--o{ B : x")
    local a, b
    for _, l in ipairs(lines) do
      a = a or (l:find("日本", 1, true) and l)
      b = b or (l:find("int", 1, true) and l)
    end
    assert.equals(text.width(b), text.width(a))
    assert.is_truthy(a:find("日本 id PK", 1, true))
    assert.is_truthy(b:find("int  n", 1, true))
    assert.is_truthy(joined(lines):find("│ B │", 1, true))
  end)

  it("draws a self-relationship", function()
    local lines = draw(60, "unicode", "A ||--o{ A : parent")
    assert.is_truthy(joined(lines):find("A", 1, true))
    assert.is_truthy(joined(lines):find("parent", 1, true))
  end)

  it("never exceeds the width and falls back to boxed source", function()
    local src = { "A ||--o{ B : places", "B ||--|{ C : has", "C }o--o{ D : x" }
    for _, w in ipairs({ 80, 40, 20, 10, 5, 1 }) do
      for _, l in ipairs(draw(w, "unicode", unpack(src))) do
        assert.is_true(text.width(l) <= w, w .. ": " .. l)
      end
    end
    assert.is_truthy(joined(draw(10, "unicode", "direction LR", unpack(src))):find("A %|%|"))
  end)

  it("keeps entities apart and ends outside the boxes", function()
    local lines = draw(80, "unicode", "A ||--o{ B", "B |o--|{ C", "A ||--|| C")
    for _, l in ipairs(lines) do
      assert.is_false(l:find("┴│", 1, true) ~= nil)
    end
  end)
end)

describe("er through the engine", function()
  it("is registered and draws", function()
    local o = mermaid.render({ "erDiagram", "A ||--o{ B : x" }, { width = 60 })
    assert.is_truthy(table.concat(o.lines, "\n"):find("│ A │", 1, true))
    for _, l in ipairs(o.lines) do
      assert.is_true(vim.fn.strdisplaywidth(l) <= 60)
    end
  end)
end)
