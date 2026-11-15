local draw = require("doc_preview.graph.draw")
local flowchart = require("doc_preview.mermaid.flowchart")
local layout = require("doc_preview.graph.layout")
local text = require("doc_preview.core.text")

local function lay_of(src, compact)
  local g = flowchart.parse(vim.split(src, "\n"))
  return g, layout.layout(g, { compact = compact })
end

local function rows(src, ctx)
  local g = draw.fit(flowchart.parse(vim.split(src, "\n")), (ctx or { width = 80 }).width)
  return draw.draw(g, layout.layout(g), ctx or { width = 80 }).lines
end

local function inside(b, n)
  return n.x >= b.x and n.y >= b.y and n.x + n.w <= b.x + b.w and n.y + n.h <= b.y + b.h
end

local function apart(a, b)
  return a.x + a.w <= b.x or b.x + b.w <= a.x or a.y + a.h <= b.y or b.y + b.h <= a.y
end

-- Node ids of a subgraph including nested ones.
local function members(g, sg, out)
  out = out or {}
  for _, id in ipairs(sg.nodes) do
    out[id] = true
  end
  for _, id in ipairs(sg.children) do
    members(g, g.sub_by_id[id], out)
  end
  return out
end

local function assert_nodes_vs_box(g, lay, sg, box)
  local own = members(g, sg)
  for id, b in pairs(lay.nodes) do
    if own[id] or id == sg.id then
      assert.is_true(id == sg.id or inside(box, b), id .. " inside " .. sg.id)
    else
      assert.is_true(apart(box, b), id .. " outside " .. sg.id)
    end
  end
end

local function assert_dummies_vs_box(lay, sg, box)
  for key, b in pairs(lay.dummies) do
    if not inside(box, b) then
      assert.is_true(apart(box, b), key .. " outside " .. sg.id)
    end
  end
end

local function assert_subgraph(g, lay, sg)
  local box = lay.clusters[sg.id]
  assert.is_truthy(box, sg.id)
  assert.is_true(
    box.x >= 0 and box.y >= 0 and box.x + box.w <= lay.width and box.y + box.h <= lay.height
  )
  assert_nodes_vs_box(g, lay, sg, box)
  assert_dummies_vs_box(lay, sg, box)
  if sg.parent then
    assert.is_true(inside(lay.clusters[sg.parent], box), "nested in " .. sg.parent)
  end
end

local function assert_pair_apart(g, lay, a, b)
  local nested = members(g, a)[b.id] ~= nil or a.id == b.parent or b.id == a.parent
  local related = inside(lay.clusters[a.id], lay.clusters[b.id])
    or inside(lay.clusters[b.id], lay.clusters[a.id])
  if not related then
    assert.is_true(
      apart(lay.clusters[a.id], lay.clusters[b.id]) or nested,
      a.id .. " apart from " .. b.id
    )
  end
end

local function assert_cluster_invariants(g, lay)
  for _, sg in ipairs(g.subgraphs) do
    assert_subgraph(g, lay, sg)
  end
  for i, a in ipairs(g.subgraphs) do
    for j, b in ipairs(g.subgraphs) do
      if i < j then
        assert_pair_apart(g, lay, a, b)
      end
    end
  end
end

local SAMPLES = {
  "graph TD\nsubgraph S [Group]\nA --> B\nend\nX --> A\nB --> Y",
  "graph TD\nsubgraph O [Outer]\nsubgraph I [Inner]\nA\nend\nB\nend\nA --> B\nC --> O",
  "graph LR\nsubgraph S [A long title here]\nA --> B\nend\nB --> C\nsubgraph E\nend\nC --> E",
  "graph TD\nsubgraph S\nA --> C\nend\nA --> B --> C\nB --> D",
  "graph BT\nsubgraph S [Left]\nA --> B\nend\nsubgraph T [Right]\nC --> D\nend\nB --> C\nA --> D",
  "graph RL\nsubgraph S\nsubgraph T\nA\nend\nB\nend\nX --> A\nB --> Y\nS --> Z",
  "graph TD\nsubgraph S\nA --> B --> C\nend\nsubgraph T\nD --> E\nend\nA --> D\nE --> C\nX --> S\nT --> X",
  "graph TD\nsubgraph S\nend\nsubgraph T\nA\nend\nS --> T\nB --> S\nB --> A",
}

describe("graph cluster layout", function()
  for n, src in ipairs(SAMPLES) do
    for _, compact in ipairs({ false, true }) do
      it(
        ("sample %d compact=%s: members inside, others outside"):format(n, tostring(compact)),
        function()
          local g, lay = lay_of(src, compact)
          assert_cluster_invariants(g, lay)
        end
      )
    end

    it(("sample %d is deterministic and fits every width"):format(n), function()
      local _, a = lay_of(src)
      local _, b = lay_of(src)
      assert.same(a, b)
      for _, charset in ipairs({ "unicode", "ascii" }) do
        for w = 1, 30 do
          for _, line in ipairs(rows(src, { width = w, charset = charset })) do
            assert.is_true(text.width(line) <= w, line)
          end
        end
      end
    end)
  end

  it("draws one cluster with its title and an edge in and out", function()
    assert.same({
      "  ┌───┐",
      "  │ X │",
      "  └───┘",
      "    │",
      "    │",
      "    │",
      "┌─ Group ─┐",
      "│   ▼     │",
      "│ ┌───┐   │",
      "│ │ A │   │",
      "│ └───┘   │",
      "│   │     │",
      "│   │     │",
      "│   ▼     │",
      "│ ┌───┐   │",
      "│ │ B │   │",
      "│ └───┘   │",
      "│   │     │",
      "└───┼─────┘",
      "    │",
      "    │",
      "    ▼",
      "  ┌───┐",
      "  │ Y │",
      "  └───┘",
    }, rows(SAMPLES[1]))
  end)

  it("nests clusters and ends an edge to a subgraph id at its first member", function()
    local g, lay = lay_of(SAMPLES[2])
    assert.is_true(inside(lay.clusters.O, lay.clusters.I))
    assert.equals("B", lay.edges[2].keys[#lay.edges[2].keys])
    assert_cluster_invariants(g, lay)
  end)

  it("lays out an empty subgraph as a titled box", function()
    local g, lay = lay_of("graph TD\nsubgraph E [Empty]\nend\nA --> E")
    assert.is_true(lay.clusters.E.w >= text.width("Empty") + 6)
    assert.same({ "A", "E" }, lay.edges[1].keys)
    local out = table.concat(rows("graph TD\nsubgraph E [Empty]\nend\nA --> E"), "\n")
    assert.is_truthy(out:find("┌─ Empty ─┐", 1, true))
    assert_cluster_invariants(g, lay)
  end)

  it("ignores edges from a subgraph to its own member and subgraph self edges", function()
    local _, lay = lay_of("graph TD\nsubgraph S\nA\nend\nS --> A\nS --> S")
    assert.is_nil(lay.edges[1])
    assert.is_nil(lay.edges[2])
  end)

  it("ignores a subgraph direction without error", function()
    local out = rows("graph TD\nsubgraph S\ndirection LR\nA --> B\nend")
    assert.is_true(#out > 0)
  end)

  it("keeps edge labels out of clusters that hold neither end", function()
    local g, lay = lay_of("graph TD\nA -->|via| D\nsubgraph S\nB --> C\nend\nA --> B")
    local out = rows("graph TD\nA -->|via| D\nsubgraph S\nB --> C\nend\nA --> B")
    assert.is_truthy(table.concat(out, "\n"):find("via", 1, true))
    assert_cluster_invariants(g, lay)
  end)

  it("draws ascii clusters with ascii glyphs only", function()
    for _, src in ipairs(SAMPLES) do
      for _, line in ipairs(rows(src, { width = 80, charset = "ascii" })) do
        assert.is_nil(line:find("[\128-\255]"), line)
      end
    end
  end)
end)
