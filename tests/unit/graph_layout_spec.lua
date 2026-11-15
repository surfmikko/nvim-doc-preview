local model = require("doc_preview.graph.model")
local layout = require("doc_preview.graph.layout")

local function graph(dir, edges, extra)
  local g = model.new(dir)
  for _, id in ipairs(extra or {}) do
    model.add_node(g, id)
  end
  for _, e in ipairs(edges) do
    model.add_node(g, e[1])
    model.add_node(g, e[2])
    model.add_edge(g, e[1], e[2], e[3])
  end
  return g
end

local function layer_of(l, id)
  for i, keys in ipairs(l.layers) do
    for _, k in ipairs(keys) do
      if k == id then
        return i
      end
    end
  end
end

local function boxes(l)
  local all = {}
  for _, b in pairs(l.nodes) do
    all[#all + 1] = b
  end
  for _, b in pairs(l.dummies) do
    all[#all + 1] = b
  end
  return all
end

local function assert_no_overlap(l)
  local all = boxes(l)
  for i = 1, #all do
    for j = i + 1, #all do
      local a, b = all[i], all[j]
      local apart = a.x + a.w <= b.x or b.x + b.w <= a.x or a.y + a.h <= b.y or b.y + b.h <= a.y
      assert.is_true(apart, "boxes overlap")
    end
  end
  for _, b in ipairs(all) do
    assert.is_true(b.x >= 0 and b.y >= 0 and b.x + b.w <= l.width and b.y + b.h <= l.height)
  end
end

local function assert_layers_follow_edges(g, l)
  for i, _ in ipairs(g.edges) do
    local info = l.edges[i]
    if info and not info.loop then
      local first, last = info.keys[1], info.keys[#info.keys]
      assert.is_true(layer_of(l, first) < layer_of(l, last))
    end
  end
end

describe("graph.layout", function()
  it("lays out an empty graph", function()
    local l = layout.layout(model.new())
    assert.equals(0, l.width)
    assert.same({}, l.layers)
  end)

  it("stacks a chain in successive layers, centred", function()
    local g = graph("TD", { { "A", "B" }, { "B", "C" } })
    local l = layout.layout(g)
    assert.same({ { "A" }, { "B" }, { "C" } }, l.layers)
    assert.equals(0, l.nodes.A.x)
    assert.equals(0, l.nodes.C.x)
    assert.equals(0, l.nodes.A.y)
    assert.equals(3 + 3, l.nodes.B.y)
    assert.equals(3, l.nodes.A.h)
    assert.equals(5, l.nodes.A.w)
    assert_no_overlap(l)
    assert_layers_follow_edges(g, l)
  end)

  it("fans out into one layer", function()
    local g = graph("TD", { { "A", "B" }, { "A", "C" }, { "A", "D" } })
    local l = layout.layout(g)
    assert.same({ "B", "C", "D" }, l.layers[2])
    assert.is_true(l.nodes.B.x < l.nodes.C.x and l.nodes.C.x < l.nodes.D.x)
    assert.equals(l.nodes.C.x, l.nodes.A.x)
    assert_no_overlap(l)
  end)

  it("lays out a diamond with the join centred", function()
    local g = graph("TD", { { "A", "B" }, { "A", "C" }, { "B", "D" }, { "C", "D" } })
    local l = layout.layout(g)
    assert.equals(3, #l.layers)
    assert.equals(l.nodes.A.x, l.nodes.D.x)
    assert_no_overlap(l)
    assert_layers_follow_edges(g, l)
  end)

  it("reverses the back edge of a cycle", function()
    local g = graph("TD", { { "A", "B" }, { "B", "C" }, { "C", "A" } })
    local l = layout.layout(g)
    assert.is_false(l.edges[1].reversed)
    assert.is_true(l.edges[3].reversed)
    local keys = l.edges[3].keys
    assert.equals("A", keys[1])
    assert.equals("C", keys[#keys])
    assert_layers_follow_edges(g, l)
    assert_no_overlap(l)
  end)

  it("marks a self-loop and keeps it out of layering", function()
    local g = graph("TD", { { "A", "A" }, { "A", "B" } })
    local l = layout.layout(g)
    assert.is_true(l.edges[1].loop)
    assert.same({ { "A" }, { "B" } }, l.layers)
  end)

  it("puts disconnected components side by side in layer one", function()
    local g = graph("TD", { { "A", "B" }, { "C", "D" } }, { "E" })
    local l = layout.layout(g)
    assert.equals(3, #l.layers[1])
    assert.equals(2, #l.layers[2])
    assert_no_overlap(l)
  end)

  it("adds dummy nodes for edges spanning layers", function()
    local g = graph("TD", { { "A", "B" }, { "B", "C" }, { "A", "C" } })
    local l = layout.layout(g)
    local keys = l.edges[3].keys
    assert.equals(3, #keys)
    assert.equals("A", keys[1])
    assert.equals("C", keys[3])
    assert.is_not_nil(l.dummies[keys[2]])
    assert.equals(2, layer_of(l, keys[2]))
    assert.equals(2, #l.layers[2])
    assert_no_overlap(l)
  end)

  it("honours the rank length of an edge", function()
    local g = graph("TD", { { "A", "B", { length = 3 } } })
    local l = layout.layout(g)
    assert.equals(3, layer_of(l, "B") - layer_of(l, "A"))
  end)

  it("orders a layer to avoid a crossing", function()
    local g = graph("TD", { { "A", "D" }, { "B", "C" } }, { "A", "B" })
    local l = layout.layout(g)
    assert.is_true((l.nodes.A.x < l.nodes.B.x) == (l.nodes.D.x < l.nodes.C.x))
  end)

  it("sizes nodes from labels", function()
    local g = model.new()
    model.add_node(g, "A", "hello\nhi")
    local l = layout.layout(g)
    assert.equals(9, l.nodes.A.w)
    assert.equals(4, l.nodes.A.h)
  end)

  it("lays out LR left to right", function()
    local g = graph("LR", { { "A", "B" }, { "A", "C" } })
    local l = layout.layout(g)
    assert.is_true(l.nodes.A.x + l.nodes.A.w < l.nodes.B.x)
    assert.equals(l.nodes.B.x, l.nodes.C.x)
    assert.is_true(l.nodes.B.y ~= l.nodes.C.y)
    assert_no_overlap(l)
  end)

  it("flips BT and RL", function()
    local bt = layout.layout(graph("BT", { { "A", "B" } }))
    assert.is_true(bt.nodes.A.y > bt.nodes.B.y)
    local rl = layout.layout(graph("RL", { { "A", "B" } }))
    assert.is_true(rl.nodes.A.x > rl.nodes.B.x)
    assert.same({ { "A" }, { "B" } }, rl.layers)
    assert_no_overlap(bt)
    assert_no_overlap(rl)
  end)

  it("compact spacing is smaller", function()
    local g = graph("TD", { { "A", "B" }, { "A", "C" } })
    local a, b = layout.layout(g), layout.layout(g, { compact = true })
    assert.is_true(b.width < a.width and b.height < a.height)
  end)

  it("ignores edges to unknown ids (subgraphs, task 10)", function()
    local g = graph("TD", { { "A", "B" } })
    g.edges[#g.edges + 1] =
      { from = "A", to = "SG", style = "solid", head = "arrow", tail = "none", length = 1 }
    local l = layout.layout(g)
    assert.is_nil(l.edges[2])
  end)

  it("is deterministic", function()
    local g = graph("TD", { { "A", "B" }, { "A", "C" }, { "B", "D" }, { "C", "D" }, { "D", "A" } })
    assert.same(layout.layout(g), layout.layout(g))
  end)

  it("handles a medium graph quickly", function()
    local g = model.new("TD")
    for i = 1, 60 do
      model.add_node(g, "N" .. i)
    end
    for i = 1, 60 do
      for _, j in ipairs({ i * 2, i * 2 + 1, i + 7 }) do
        if j <= 60 then
          model.add_edge(g, "N" .. i, "N" .. j)
        end
      end
    end
    model.add_edge(g, "N60", "N1")
    local t0 = vim.uv.hrtime()
    local l = layout.layout(g)
    local ms = (vim.uv.hrtime() - t0) / 1e6
    print(("layout of 60 nodes: %.1f ms (budget 100)"):format(ms))
    assert.is_true(ms < 1000)
    assert_no_overlap(l)
    assert_layers_follow_edges(g, l)
  end)
end)
