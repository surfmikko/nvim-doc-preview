local flowchart = require("doc_preview.mermaid.flowchart")
local mermaid = require("doc_preview.mermaid")
local model = require("doc_preview.graph.model")
local shapes = require("doc_preview.graph.shapes")
local text = require("doc_preview.core.text")

local function check_width(o, width)
  for _, l in ipairs(o.lines) do
    assert.is_true(text.width(l) <= width, l)
  end
end

describe("flowchart.parse", function()
  it("reads header and nodes", function()
    local g = flowchart.parse({ "flowchart LR", "A", "B[Bee]", 'C["Sea; x"]' })
    assert.equals("LR", g.direction)
    assert.is_true(model.validate(g))
    assert.same({ "A", "Bee", "Sea; x" }, { g.nodes[1].label, g.nodes[2].label, g.nodes[3].label })
    assert.equals("rect", g.nodes[2].shape)
  end)

  it("accepts graph alias, TB, and default direction", function()
    assert.equals("TD", flowchart.parse({ "graph TB" }).direction)
    assert.equals("TD", flowchart.parse({ "graph" }).direction)
    assert.equals("BT", flowchart.parse({ "graph BT;" }).direction)
  end)

  it("splits on semicolons and skips comments, frontmatter, directives", function()
    local g = flowchart.parse({
      "---",
      "title: t",
      "---",
      "%%{init: {}}%%",
      "flowchart TD; A; B[b]",
      "%% comment",
      "  C ;",
      "",
    })
    assert.equals(3, #g.nodes)
    assert.equals("C", g.nodes[3].id)
  end)

  it("later label wins on redeclaration", function()
    local g = flowchart.parse({ "graph TD", "A[x]", "A", "A[y]" })
    assert.equals(1, #g.nodes)
    assert.equals("y", g.nodes[1].label)
  end)

  it("errors on bad header, bad direction and broken syntax with the line", function()
    assert.has_error(function()
      flowchart.parse({ "graph XX" })
    end, "line 1: unknown direction XX")
    assert.has_error(function()
      flowchart.parse({ "graph TD", "A[", "" })
    end, "line 2: syntax error: A[")
    assert.has_error(function()
      flowchart.parse({ "graph TD", "A -->" })
    end, "line 2: syntax error: A -->")
    assert.has_error(function()
      flowchart.parse({ "graph TD", "A -- B" })
    end, "line 2: syntax error: A -- B")
    assert.has_error(function()
      flowchart.parse({ "graph TD", "A --> B ??" })
    end, "line 2: syntax error: A --> B ??")
  end)

  it("never throws a non-string error on garbage", function()
    for _, bad in ipairs({
      "-->",
      "&",
      "A &",
      'A["x',
      "A -->|x B",
      "A ==",
      "((",
      "A -. x",
      "<--> B",
    }) do
      local ok, err = pcall(flowchart.parse, { "graph TD", bad })
      assert.is_false(ok, bad)
      assert.is_string(err)
    end
  end)
end)

local function edge(g, i)
  local e = g.edges[i]
  return { e.from, e.to, e.style, e.head, e.tail, e.length, e.label }
end

describe("flowchart.parse shapes", function()
  it("maps delimiters to shape names", function()
    local src = {
      "graph TD",
      "a[x]",
      "b(x)",
      "c([x])",
      "d[[x]]",
      "e((x))",
      "f{x}",
      "g{{x}}",
      "h[(x)]",
      "i>x]",
    }
    local g = flowchart.parse(src)
    local got = {}
    for i, n in ipairs(g.nodes) do
      got[i] = n.shape
    end
    assert.same({
      "rect",
      "round",
      "stadium",
      "subroutine",
      "circle",
      "rhombus",
      "hexagon",
      "cylinder",
      "rect",
    }, got)
  end)

  it("lets a later explicit shape win and keeps it when omitted", function()
    local g = flowchart.parse({ "graph TD", "A --> B", "B{c}", "B" })
    assert.equals("rhombus", g.by_id.B.shape)
  end)
end)

describe("flowchart.parse edges", function()
  it("reads operators", function()
    local g = flowchart.parse({
      "graph TD",
      "A-->B",
      "A---C",
      "A-.->D",
      "A==>E",
      "A--oF",
      "A--xG",
      "A<-->H",
    })
    assert.is_true(model.validate(g))
    assert.same({ "A", "B", "solid", "arrow", "none", 1 }, edge(g, 1))
    assert.same({ "A", "C", "solid", "none", "none", 1 }, edge(g, 2))
    assert.same({ "A", "D", "dotted", "arrow", "none", 1 }, edge(g, 3))
    assert.same({ "A", "E", "thick", "arrow", "none", 1 }, edge(g, 4))
    assert.same({ "A", "F", "solid", "circle", "none", 1 }, edge(g, 5))
    assert.same({ "A", "G", "solid", "cross", "none", 1 }, edge(g, 6))
    assert.same({ "A", "H", "solid", "arrow", "arrow", 1 }, edge(g, 7))
  end)

  it("reads rank length", function()
    local g =
      flowchart.parse({ "graph TD", "A --> B", "A ---> C", "A --- D", "A ---- E", "A -..-> F" })
    local lens = {}
    for i = 1, 5 do
      lens[i] = g.edges[i].length
    end
    assert.same({ 1, 2, 1, 2, 2 }, lens)
  end)

  it("reads both label forms and br", function()
    local g = flowchart.parse({ "graph TD", "A -->|a<br/>b| B", "A -- t --> C", 'A -- "q" --- D' })
    assert.equals("a\nb", g.edges[1].label)
    assert.same({ "A", "C", "solid", "arrow", "none", 1, "t" }, edge(g, 2))
    assert.same({ "A", "D", "solid", "none", "none", 1, "q" }, edge(g, 3))
  end)

  it("expands chains and fan-in/out in order", function()
    local g = flowchart.parse({ "graph TD", "A --> B --> C", "X & Y --> Z" })
    assert.equals(4, #g.edges)
    assert.same({ "B", "C" }, { g.edges[2].from, g.edges[2].to })
    assert.same({ "X", "Z" }, { g.edges[3].from, g.edges[3].to })
    assert.same({ "Y", "Z" }, { g.edges[4].from, g.edges[4].to })
    assert.same(
      { "A", "B", "C", "X", "Y", "Z" },
      vim.tbl_map(function(n)
        return n.id
      end, g.nodes)
    )
  end)

  it("declares shapes on edge endpoints", function()
    local g = flowchart.parse({ "graph TD", "A[Start] --> B{Ok?}" })
    assert.equals("Start", g.by_id.A.label)
    assert.equals("rhombus", g.by_id.B.shape)
  end)

  it("ignores styling statements, but not nodes named like them", function()
    local g = flowchart.parse({
      "graph TD",
      "classDef a fill:#fff",
      "class A a",
      "style A fill:#f00",
      "linkStyle 0 stroke:red",
      'click A cb "t"',
      "style1 --> B",
    })
    assert.same(
      { "style1", "B" },
      vim.tbl_map(function(n)
        return n.id
      end, g.nodes)
    )
    assert.equals(1, #g.edges)
  end)

  it("treats quoted and markdown-string labels as plain text", function()
    local g = flowchart.parse({ "graph TD", 'A["x<br>y"]', 'B["`**m**`"]', 'C["a]b"]' })
    assert.same(
      { "x\ny", "**m**", "a]b" },
      { g.nodes[1].label, g.nodes[2].label, g.nodes[3].label }
    )
  end)
end)

describe("flowchart subgraphs", function()
  local function sg(g, id)
    return g.sub_by_id[id]
  end

  it("records nesting, membership and titles", function()
    local g = flowchart.parse({
      "graph TD",
      "A",
      "subgraph one [Title]",
      "  B & C",
      "  subgraph two",
      "    direction LR",
      "    D",
      "  end",
      "  A --> E",
      "end",
    })
    assert.same({ "B", "C", "E" }, sg(g, "one").nodes)
    assert.same({ "D" }, sg(g, "two").nodes)
    assert.equals("Title", sg(g, "one").title)
    assert.equals("two", sg(g, "two").title)
    assert.equals("one", sg(g, "two").parent)
    assert.same({ "two" }, sg(g, "one").children)
    assert.equals("LR", sg(g, "two").direction)
    assert.is_true(model.validate(g))
  end)

  it("keeps a node in the subgraph where it was first declared", function()
    local g = flowchart.parse({ "graph TD", "subgraph s", "A", "end", "A --> B" })
    assert.same({ "A" }, sg(g, "s").nodes)
  end)

  it("accepts a spaced title and edges to subgraph ids", function()
    local g = flowchart.parse({
      "graph TD",
      "subgraph my group",
      "A",
      "end",
      "subgraph s [t]",
      "end",
      "B --> s",
    })
    assert.same(
      { "A", "B" },
      vim.tbl_map(function(n)
        return n.id
      end, g.nodes)
    )
    assert.equals("s", g.edges[1].to)
    assert.equals("my group", g.subgraphs[1].title)
    assert.is_true(model.validate(g))
  end)

  it("redeclaration: later label wins and an explicit shape replaces", function()
    local g = flowchart.parse({ "graph TD", "A[x]", "A{y}", "A" })
    assert.equals("y", g.nodes[1].label)
    assert.equals("rhombus", g.nodes[1].shape)
  end)

  it("errors on unterminated subgraph, stray end and misplaced direction", function()
    assert.has_error(function()
      flowchart.parse({ "graph TD", "subgraph a", "subgraph b", "end" })
    end, "line 2: subgraph a is not closed")
    assert.has_error(function()
      flowchart.parse({ "graph TD", "end" })
    end, "line 2: end without subgraph")
    assert.has_error(function()
      flowchart.parse({ "graph TD", "direction LR" })
    end, "line 2: direction outside subgraph")
    assert.has_error(function()
      flowchart.parse({ "graph TD", "subgraph a", "direction XX", "end" })
    end, "line 3: unknown direction XX")
    assert.has_error(function()
      flowchart.parse({ "graph TD", "subgraph", "end" })
    end, "line 2: subgraph needs an id or title")
    assert.has_error(function()
      flowchart.parse({ "graph TD", "subgraph a", "end", "subgraph a", "end" })
    end, "line 4: duplicate subgraph a")
  end)

  it("never throws anything but a plain string on garbage", function()
    local junk = {
      "subgraph",
      "end",
      "A -->",
      "[[",
      "((",
      "A[",
      "-->",
      "&",
      "|x|",
      "direction",
      "A --- & B",
      'A["',
      "subgraph [",
      "subgraph a [",
      "\0",
      "A --> --> B",
      "end end",
      ";;;",
      "%%",
      "A & --> B",
    }
    math.randomseed(42)
    for _ = 1, 300 do
      local lines = { "flowchart TD" }
      for _ = 1, math.random(1, 6) do
        lines[#lines + 1] = junk[math.random(#junk)]
      end
      local ok, res = pcall(flowchart.parse, lines)
      assert.is_true(ok or type(res) == "string", vim.inspect(lines))
      local o = mermaid.render(lines, { width = 20 })
      assert.is_table(o.lines)
    end
  end)
end)

describe("graph.shapes", function()
  it("falls back to rect", function()
    assert.equals(shapes.get("rect"), shapes.get("nonsense"))
    assert.equals(shapes.get("rect"), shapes.get(nil))
  end)
end)

describe("flowchart render", function()
  it("draws one node", function()
    local o = mermaid.render({ "flowchart TD", "A[Hello]" }, { width = 40 })
    assert.same(
      { "┌───────┐", "│ Hello │", "└───────┘" },
      o.lines
    )
    assert.equals("DocPreviewDiagramBorder", o.spans[1].hl_group)
  end)

  it("puts unconnected nodes side by side, ascii charset", function()
    local o = mermaid.render({ "graph TD", "A", "Bee" }, { width = 40, charset = "ascii" })
    assert.same({ "+---+    +-----+", "| A |    | Bee |", "+---+    +-----+" }, o.lines)
  end)

  it("pads wide labels by display width", function()
    local o = mermaid.render({ "graph TD", "A[日本]" }, { width = 40 })
    assert.equals("│ 日本 │", o.lines[2])
    assert.equals(text.width(o.lines[1]), text.width(o.lines[2]))
  end)

  it("truncates labels wider than the width", function()
    for _, label in ipairs({ ("x"):rep(50), ("日"):rep(30) }) do
      for w = 1, 20 do
        local o = mermaid.render({ "graph TD", "A[" .. label .. "]" }, { width = w })
        check_width(o, w)
      end
    end
    local o = mermaid.render({ "graph TD", "A[" .. ("x"):rep(50) .. "]" }, { width = 10 })
    assert.equals("│ xxx... │", o.lines[2])
  end)

  it("draws an edge with an arrowhead", function()
    local o = mermaid.render({ "graph TD", "A --> B" }, { width = 40 })
    assert.same({
      "┌───┐",
      "│ A │",
      "└───┘",
      "  │",
      "  │",
      "  ▼",
      "┌───┐",
      "│ B │",
      "└───┘",
    }, o.lines)
  end)

  it("draws multi-line labels and shows an errbox for syntax errors and no nodes", function()
    local o = mermaid.render({ "graph TD", 'A["x<br/>yy"]' }, { width = 40 })
    assert.same({ "┌────┐", "│ x  │", "│ yy │", "└────┘" }, o.lines)
    o = mermaid.render({ "graph TD", "A -->" }, { width = 60 })
    assert.is_truthy(o.lines[2]:find("syntax error", 1, true))
    o = mermaid.render({ "graph TD" }, { width = 60 })
    assert.is_truthy(o.lines[2]:find("no nodes", 1, true))
  end)
end)

describe("flowchart width policy", function()
  local LR = { "graph LR", "A[Alpha] --> B[Beta] --> C[Gamma]" }

  local function rows(src, ctx)
    local o = mermaid.render(src, ctx)
    check_width(o, ctx.width)
    return o.lines
  end

  it("keeps the normal spacing when the diagram fits", function()
    local wide = rows(LR, { width = 80 })
    assert.is_true(text.width(wide[2]) > 20)
    assert.is_nil(table.concat(wide, "\n"):find("wider", 1, true))
  end)

  it("uses compact spacing before anything else", function()
    local normal = rows(LR, { width = 80 })
    local w = text.width(normal[2])
    local lines = rows(LR, { width = w - 1 })
    assert.is_true(#lines == #normal, "still left to right")
    assert.is_true(text.width(lines[2]) < w)
  end)

  it("turns LR top-down when compact spacing is not enough", function()
    local lines = rows(LR, { width = 15 })
    assert.is_true(#lines > 3)
    assert.is_truthy(table.concat(lines, "\n"):find("▼", 1, true))
  end)

  it("falls back to the boxed source with a note for TD", function()
    local lines = rows({ "graph TD", "A[Alpha] --> B", "A --> C", "A --> D" }, { width = 14 })
    assert.equals("┌", lines[1]:sub(1, 3))
    assert.is_truthy(table.concat(lines):gsub("[│ ]", ""):find("widerthan14columns", 1, true))
    assert.is_truthy(table.concat(lines, "\n"):find("A --> C", 1, true))
  end)

  it("never exceeds any width", function()
    local srcs = {
      LR,
      { "graph TD", "subgraph S [Group]", "A --> B", "end", "B -->|yes| C{Q}", "C --> A" },
      { "graph RL", "A((a)) -.-> B[[b]]", "B ==> C{{c}}", "C --o A" },
    }
    for _, src in ipairs(srcs) do
      for w = 1, 60 do
        rows(src, { width = w })
        rows(src, { width = w, charset = "ascii" })
      end
    end
  end)

  it("yields to the job runner while laying out and drawing", function()
    local job = require("doc_preview.core.job")
    local real, n = job.yield_point, 0
    job.yield_point = function()
      n = n + 1
    end
    mermaid.render({ "graph TD", "A --> B --> C", "A --> C" }, { width = 40 })
    job.yield_point = real
    assert.is_true(n > 0)
  end)
end)
