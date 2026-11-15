local class = require("doc_preview.mermaid.class")
local mermaid = require("doc_preview.mermaid")
local model = require("doc_preview.graph.model")
local syntax = require("doc_preview.mermaid.class_syntax")
local text = require("doc_preview.core.text")

local function parse(...)
  return class.parse({ "classDiagram", ... })
end

describe("class.parse", function()
  it("reads header variants and direction", function()
    assert.equals("TD", class.parse({ "classDiagram" }).direction)
    assert.equals("LR", class.parse({ "classDiagram-v2", "direction LR" }).direction)
    assert.equals("TD", parse("direction TB").direction)
    assert.has_error(function()
      class.parse({ "graph TD" })
    end, "line 1: expected classDiagram")
    assert.has_error(function()
      parse("direction XX")
    end, "line 2: unknown direction XX")
  end)

  it("builds record nodes with annotation, member and method sections", function()
    local g = parse("class A {", "  <<interface>>", "  +int x", "  -y$", "  +run() void", "}")
    assert.is_true(model.validate(g))
    local n = g.by_id.A
    assert.equals("record", n.shape)
    assert.same({ { "<<interface>>" }, { "+int x", "-y$" }, { "+run() void" } }, n.rows)
  end)

  it("leaves rows nil for an empty class", function()
    assert.is_nil(parse("class A").by_id.A.rows)
  end)

  it("reads `Name : member` and `<<annotation>> Name` lines", function()
    local g = parse("A : +x", "A : +f(a) int", "<<enum>> A")
    assert.same({ "+x" }, g.classes.A.members)
    assert.same({ "+f(a) int" }, g.classes.A.methods)
    assert.equals("enum", g.classes.A.annotation)
  end)

  it("shows generics as <T> and keeps the id plain", function()
    local g = parse("class List~T~", "List : +add(Map~K,V~ m)")
    assert.equals("List<T>", g.by_id.List.label)
    assert.same({ "+add(Map<K,V> m)" }, g.classes.List.methods)
    assert.equals("A<T>", syntax.generics("A~T~"))
  end)

  it("accepts backquoted names and labels", function()
    local g = parse("class `My Class`", 'class B["Bee"]', "`My Class` --> B")
    assert.equals("My Class", g.by_id["My Class"].label)
    assert.equals("Bee", g.by_id.B.label)
    assert.equals(1, #g.edges)
  end)

  it("maps every relation operator", function()
    local cases = {
      { "A <|-- B", "triangle", "none", "solid" },
      { "A --|> B", "none", "triangle", "solid" },
      { "A *-- B", "diamond_filled", "none", "solid" },
      { "A o-- B", "diamond", "none", "solid" },
      { "A --> B", "none", "arrow", "solid" },
      { "A <-- B", "arrow", "none", "solid" },
      { "A -- B", "none", "none", "solid" },
      { "A ..> B", "none", "arrow", "dotted" },
      { "A ..|> B", "none", "triangle", "dotted" },
      { "A .. B", "none", "none", "dotted" },
    }
    for _, c in ipairs(cases) do
      local e = parse(c[1]).edges[1]
      assert.same({ c[2], c[3], c[4] }, { e.tail_kind, e.head_kind, e.style }, c[1])
    end
  end)

  it("reads cardinalities and the label", function()
    local e = parse('A "1" --> "*" B : has many').edges[1]
    assert.equals("1", e.tail_label)
    assert.equals("*", e.head_label)
    assert.equals("has many", e.label)
  end)

  it("creates implicit classes in order of first mention", function()
    local g = parse("B --> A", "C -- B")
    assert.same(
      { "B", "A", "C" },
      vim.tbl_map(function(n)
        return n.id
      end, g.nodes)
    )
  end)

  it("turns a namespace into a cluster of the classes declared inside", function()
    local g = parse("namespace N {", "  class A", "  class B {", "    +x", "  }", "}", "class C")
    assert.is_true(model.validate(g))
    assert.same({ "A", "B" }, g.sub_by_id.N.nodes)
    assert.same({ { "+x" } }, g.by_id.B.rows)
  end)

  it("adds notes as record nodes joined by a dotted edge", function()
    local g = parse("class A", 'note "free"', 'note for A "x<br/>y"')
    assert.is_true(model.validate(g))
    assert.equals("free", g.by_id["note:1"].label)
    assert.equals("x\ny", g.by_id["note:2"].label)
    assert.equals(1, #g.edges)
    assert.same({ "A", "note:2", "dotted" }, { g.edges[1].from, g.edges[1].to, g.edges[1].style })
  end)

  it("ignores styling and link statements", function()
    local g = parse(
      "classDef x fill:#f00",
      'cssClass "A" x',
      "style A fill:#fff",
      "click A call f()",
      "link A",
      "callback A"
    )
    assert.equals(0, #g.nodes)
  end)

  it("names the line of errors", function()
    local function err(...)
      local ok, e = pcall(parse, ...)
      assert.is_false(ok)
      return e
    end
    assert.equals("line 3: syntax error: A <|--", err("class A", "A <|--"))
    assert.equals("line 2: class A is not closed", err("class A {", "+x"))
    assert.equals("line 2: namespace N is not closed", err("namespace N {"))
    assert.equals("line 2: } without namespace or class body", err("}"))
    assert.equals("line 2: syntax error: garbage here", err("garbage here"))
  end)

  it("never throws anything but a string on garbage", function()
    local garbage = {
      "",
      "{",
      "}",
      "class",
      "class {",
      "A :",
      ": x",
      "<<",
      "note",
      'note for "',
      "A -- ",
      '"1" --> B',
      "namespace",
      "namespace X {",
      "~",
      "`",
      "A ~ B",
      "direction",
      "click",
    }
    for _, line in ipairs(garbage) do
      local ok, e = pcall(parse, line)
      assert.is_true(ok or type(e) == "string", line)
    end
  end)
end)

describe("class engine registration", function()
  local ctx = { width = 40 }

  it("renders classDiagram and -v2 inside the width", function()
    for _, header in ipairs({ "classDiagram", "classDiagram-v2" }) do
      local o = mermaid.render({ header, "A <|-- B" }, ctx)
      assert.is_true(#o.lines > 0)
      for _, l in ipairs(o.lines) do
        assert.is_true(text.width(l) <= ctx.width)
      end
    end
  end)

  it("shows the parse error line in an errbox", function()
    local o = mermaid.render({ "classDiagram", "A <|--" }, { width = 80 })
    assert.is_truthy(table.concat(o.lines, "\n"):find("line 2: syntax error", 1, true))
  end)
end)

describe("class.render", function()
  local function rows(src, width, extra)
    local ctx = vim.tbl_extend("force", { width = width or 80 }, extra or {})
    return class.render(vim.split("classDiagram\n" .. src, "\n"), ctx).lines
  end

  local function joined(lines)
    return table.concat(lines, "\n")
  end

  it("draws one record box holding every member and method", function()
    local out = joined(rows("class A {\n<<interface>>\n+int x\n-y\n+run() void\n}"))
    for _, t in ipairs({ "<<interface>>", "+int x", "-y", "+run() void" }) do
      assert.is_truthy(out:find(t, 1, true), t)
    end
    assert.equals(3, select(2, out:gsub("├", "")))
  end)

  it("puts the glyph at the right end per relation kind", function()
    -- A is drawn above B: tail glyphs hang under A's box, head glyphs sit above B's.
    local cases = {
      { "A <|-- B", "△", "tail" },
      { "A --|> B", "▽", "head" },
      { "A *-- B", "◆", "tail" },
      { "A o-- B", "◇", "tail" },
      { "A --> B", "▼", "head" },
    }
    for _, c in ipairs(cases) do
      local lines = rows(c[1])
      local at
      for i, l in ipairs(lines) do
        if l:find(c[2], 1, true) then
          at = i
        end
      end
      assert.is_not_nil(at, c[1])
      local neighbour = lines[c[3] == "tail" and at - 1 or at + 1]
      assert.is_truthy(neighbour:find(c[3] == "tail" and "└" or "┌", 1, true), c[1])
    end
  end)

  it("draws dotted lines and cardinalities beside the ends", function()
    local out = joined(rows('A "1" ..> "*" B : uses'))
    assert.is_truthy(out:find("┆", 1, true))
    assert.is_truthy(out:find("1", 1, true))
    assert.is_truthy(out:find("*", 1, true))
    assert.is_truthy(out:find("uses", 1, true))
  end)

  it("honours direction LR and falls back top-down when narrow", function()
    local src = "direction LR\nA --> B\nB --> C"
    assert.is_truthy(joined(rows(src, 80)):find("▶", 1, true))
    local narrow = joined(rows(src, 12))
    assert.is_truthy(narrow:find("▼", 1, true))
    assert.is_falsy(narrow:find("▶", 1, true))
  end)

  it("draws a namespace as a titled cluster around its classes", function()
    local out = joined(rows("namespace ns {\nclass A\n}\nB --> A"))
    assert.is_truthy(out:find("─ ns ", 1, true))
  end)

  it("never exceeds the width and boxes the source when nothing fits", function()
    local src = "Alpha <|-- Beta\nAlpha <|-- Gamma\nAlpha <|-- Delta\nAlpha <|-- Omega"
    for _, w in ipairs({ 80, 40, 20, 12, 8 }) do
      for _, l in ipairs(rows(src, w)) do
        assert.is_true(text.width(l) <= w, w .. ": " .. l)
      end
    end
    assert.is_truthy(joined(rows(src, 40)):find("diagram wider than 40", 1, true))
  end)

  it("keeps an empty diagram an error box", function()
    local o = mermaid.render({ "classDiagram" }, { width = 40 })
    assert.is_truthy(joined(o.lines):find("no nodes", 1, true))
  end)
end)
