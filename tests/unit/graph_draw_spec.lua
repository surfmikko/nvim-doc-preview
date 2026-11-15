local draw = require("doc_preview.graph.draw")
local flowchart = require("doc_preview.mermaid.flowchart")
local layout = require("doc_preview.graph.layout")
local route = require("doc_preview.graph.route")
local shapes = require("doc_preview.graph.shapes")
local text = require("doc_preview.core.text")

local function render(src, ctx)
  local lines = vim.split(src, "\n")
  local g = draw.fit(flowchart.parse(lines), (ctx or { width = 80 }).width)
  return draw.draw(g, layout.layout(g, { compact = (ctx or {}).compact }), ctx or { width = 80 }), g
end

local function rows(src, ctx)
  return (render(src, ctx)).lines
end

describe("graph.shapes glyphs", function()
  local cases = {
    {
      "A(r)",
      { "╭───╮", "│ r │", "╰───╯" },
      { ".---.", "| r |", "'---'" },
    },
    { "A([s])", { "╭───╮", "( s )", "╰───╯" }, { ".---.", "( s )", "'---'" } },
    {
      "A[[u]]",
      { "┌┬───┬┐", "││ u ││", "└┴───┴┘" },
      { "++---++", "|| u ||", "++---++" },
    },
    {
      "A((c))",
      { "╭─────╮", "(( c ))", "╰─────╯" },
      { ".-----.", "(( c ))", "'-----'" },
    },
    { "A{d}", { "╱───╲", "< d >", "╲───╱" }, { "/---\\", "< d >", "\\---/" } },
    { "A{{h}}", { "┌───┐", "< h >", "└───┘" }, { "+---+", "< h >", "+---+" } },
    {
      "A[(y)]",
      { "╭───╮", "│ y │", "╰═══╯" },
      { ".---.", "| y |", "'==='" },
    },
    {
      "A[r]",
      { "┌───┐", "│ r │", "└───┘" },
      { "+---+", "| r |", "+---+" },
    },
  }
  for _, c in ipairs(cases) do
    it("draws " .. c[1], function()
      assert.same(c[2], rows("graph TD\n" .. c[1]))
      assert.same(c[3], rows("graph TD\n" .. c[1], { width = 80, charset = "ascii" }))
    end)
  end

  it("falls back to rect and keeps the label padding per shape", function()
    assert.equals(shapes.get("rect"), shapes.get("hexagonal"))
    assert.equals(2, shapes.get("subroutine").pad)
    assert.equals(1, shapes.get("rhombus").pad)
  end)
end)

describe("graph.draw edges", function()
  it("draws edge styles", function()
    assert.same({
      "┌───┐",
      "│ A │",
      "└───┘",
      "  ┆",
      "  ┆",
      "  ▼",
      "┌───┐",
      "│ B │",
      "└───┘",
      "  ┃",
      "  ┃",
      "  ▼",
      "┌───┐",
      "│ C │",
      "└───┘",
    }, rows("graph TD\nA -.-> B\nB ==> C"))
    assert.same({
      "+---+",
      "| A |",
      "+---+",
      "  :",
      "  :",
      "  v",
      "+---+",
      "| B |",
      "+---+",
      "  !",
      "  !",
      "  v",
      "+---+",
      "| C |",
      "+---+",
    }, rows("graph TD\nA -.-> B\nB ==> C", { width = 80, charset = "ascii" }))
  end)

  it("draws open, circle, cross and double-ended edges", function()
    local l = rows("graph TD\nA --- B\nB --o C\nC --x D\nD <--> E")
    assert.same({ "  │", "  │", "  │" }, { l[4], l[5], l[6] })
    assert.same({ "  │", "  │", "  o" }, { l[10], l[11], l[12] })
    assert.same({ "  │", "  │", "  x" }, { l[16], l[17], l[18] })
    assert.same({ "  ▲", "  │", "  ▼" }, { l[22], l[23], l[24] })
  end)

  it("points arrowheads along every direction", function()
    assert.same({
      "┌───┐        ┌───┐",
      "│ B │◀───────│ A │",
      "└───┘        └───┘",
    }, rows("graph RL\nA --> B"))
    assert.same({
      "┌───┐        ┌───┐",
      "│ A │───────▶│ B │",
      "└───┘        └───┘",
    }, rows("graph LR\nA --> B"))
    local bt = rows("graph BT\nA --> B")
    assert.equals("  ▲", bt[4])
    assert.equals("│ B │", bt[2])
  end)

  it("uses one row in compact mode", function()
    assert.same({
      "┌───┐",
      "│ A │",
      "└───┘",
      "  ▼",
      "┌───┐",
      "│ B │",
      "└───┘",
    }, rows("graph TD\nA --> B", { width = 80, compact = true }))
  end)

  it("jogs between columns and merges fan-out", function()
    local l = rows("graph TD\nA --> B\nA --> C")
    assert.same({
      "     ┌───┐",
      "     │ A │",
      "     └───┘",
      "       │",
      "  ┌────┴───┐",
      "  ▼        ▼",
    }, { l[1], l[2], l[3], l[4], l[5], l[6] })
  end)

  it("draws a back edge with its head at the target", function()
    local l = rows("graph TD\nA --> B\nB --> C\nC --> A")
    local text_ = table.concat(l, "\n")
    local _, heads = text_:gsub("▲", "")
    assert.equals(1, heads)
    local first_up
    for i, row in ipairs(l) do
      if row:find("▲", 1, true) then
        first_up = i
      end
    end
    assert.is_true(first_up < 6, "head sits just below the top node")
  end)

  it("draws a self-loop returning into the right border", function()
    assert.same(
      { "┌───┐", "│ A │◀┐", "└───┘─┘" },
      rows("graph TD\nA --> A")
    )
  end)

  it("draws edge labels beside, on and over edges", function()
    assert.same({
      "┌───┐",
      "│ A │",
      "└───┘",
      "  │",
      "  │ yes",
      "  ▼",
      "┌───┐",
      "│ B │",
      "└───┘",
    }, rows("graph TD\nA -->|yes| B"))
    assert.same({
      "┌───┐ yes    ┌───┐",
      "│ A │───────▶│ B │",
      "└───┘        └───┘",
    }, rows("graph LR\nA -->|yes| B"))
    assert.same(
      { "┌───┐", "│ A │◀┐ me", "└───┘─┘" },
      rows("graph TD\nA -->|me| A")
    )
    local l = rows('graph TD\nA -->|"a long label"| B\nA --> C')
    assert.is_truthy(table.concat(l, "\n"):find("a long label", 1, true))
  end)

  it("keeps node text intact next to labels", function()
    local l = table.concat(
      rows("graph LR\nAlpha -->|go| Beta\nAlpha -->|stop| Gamma\nBeta --> Gamma"),
      "\n"
    )
    for _, w in ipairs({ "Alpha", "Beta", "Gamma", "go", "stop" }) do
      assert.is_truthy(l:find(w, 1, true), w)
    end
  end)

  it("draws edges to subgraph ids", function()
    local o = render("graph TD\nsubgraph S\nA\nend\nB --> S")
    assert.is_truthy(table.concat(o.lines, "\n"):find("▼", 1, true))
  end)
end)

local SAMPLES = {
  "graph TD\nA --> B --> C",
  "graph TD\nA --> B\nA --> C\nB --> D\nC --> D",
  "graph TD\nA --> B\nB --> C\nC --> A",
  "graph TD\nA --> B\nB --> C\nA --> C\nA --> D\nD --> C",
  "graph LR\nA --> B\nB --> C\nA --> C\nC --> A",
  "graph RL\nA --> B\nB --> B\nA --> C",
  "graph BT\nA --> B\nA --> C\nC --> D\nA --> D",
  "graph TD\nA --> B\nC --> D\nE --> E",
  "graph TD\nA -->|one| B\nA -.->|two| C\nB ==>|three| D\nC --o D",
  "graph LR\nA --> B & C\nB & C --> D\nD --> A",
}

local function distance(b, p)
  local dx = math.max(b.x - p.x, 0, p.x - (b.x + b.w - 1))
  local dy = math.max(b.y - p.y, 0, p.y - (b.y + b.h - 1))
  return dx + dy
end

local function inside(b, p)
  return distance(b, p) == 0
end

describe("graph.route invariants", function()
  for n, src in ipairs(SAMPLES) do
    for _, compact in ipairs({ false, true }) do
      it(
        ("sample %d compact=%s: edges attach, avoid nodes, stay in bounds"):format(
          n,
          tostring(compact)
        ),
        function()
          local g = flowchart.parse(vim.split(src, "\n"))
          local lay = layout.layout(g, { compact = compact })
          local routes = route.route(g, lay)
          local cols, rows_ = route.margin(routes)
          for i, r in pairs(routes) do
            local keys = lay.edges[i].keys
            assert.is_true(
              distance(lay.nodes[keys[1]], r.first) == 1,
              "first cell touches the source"
            )
            assert.is_true(
              distance(lay.nodes[keys[#keys]], r.last) == 1,
              "last cell touches the target"
            )
            for _, poly in ipairs(r.polys) do
              for s = 1, #poly - 1 do
                assert.is_true(
                  poly[s].x == poly[s + 1].x or poly[s].y == poly[s + 1].y,
                  "orthogonal"
                )
              end
              for _, p in ipairs(poly) do
                assert.is_true(
                  p.x >= 0 and p.y >= 0 and p.x < lay.width + cols and p.y < lay.height + rows_
                )
                for _, b in pairs(lay.nodes) do
                  assert.is_false(inside(b, p), "edge cell inside a node")
                end
              end
            end
          end
        end
      )
    end

    it(("sample %d renders every label and fits every width"):format(n), function()
      local g = flowchart.parse(vim.split(src, "\n"))
      local o = render(src)
      local all = table.concat(o.lines, "\n")
      for _, node in ipairs(g.nodes) do
        assert.is_truthy(
          all:find("│ " .. node.id .. " │", 1, true)
            or all:find("| " .. node.id .. " |", 1, true)
            or all:find(node.id, 1, true)
        )
      end
      for _, e in ipairs(g.edges) do
        if e.label then
          assert.is_truthy(all:find(e.label, 1, true), e.label)
        end
      end
      for _, charset in ipairs({ "unicode", "ascii" }) do
        for w = 1, 30 do
          local out = render(src, { width = w, charset = charset })
          for _, line in ipairs(out.lines) do
            assert.is_true(text.width(line) <= w, line)
          end
        end
      end
    end)
  end

  it("draws ascii output with ascii glyphs only", function()
    for _, src in ipairs(SAMPLES) do
      for _, line in ipairs(render(src, { width = 80, charset = "ascii" }).lines) do
        assert.is_nil(line:find("[\128-\255]"), line)
      end
    end
  end)

  it("is deterministic and highlights lines as edge and labels as label", function()
    local a, b = render(SAMPLES[9]), render(SAMPLES[9])
    assert.same(a.lines, b.lines)
    local groups = {}
    for _, sp in ipairs(a.spans) do
      groups[sp.hl_group] = true
    end
    assert.is_true(
      groups.DocPreviewDiagramEdge
        and groups.DocPreviewDiagramBorder
        and groups.DocPreviewDiagramLabel
    )
  end)
end)

describe("graph.draw one-row gap", function()
  it("draws no stray line beside the arrowhead", function()
    local src = "flowchart TD\nA[Alpha] -->|go| B[Beta] --> C[Gamma] --> D[Delta]"
    for _, line in ipairs(rows(src, { width = 40, compact = true })) do
      assert.is_nil(line:find("▼─", 1, true), line)
      assert.is_nil(line:find("─▼", 1, true), line)
    end
  end)
end)
