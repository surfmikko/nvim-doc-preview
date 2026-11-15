local model = require("doc_preview.graph.model")

describe("graph.model", function()
  it("starts empty, top-down", function()
    local g = model.new()
    assert.equals("TD", g.direction)
    assert.same({}, g.nodes)
    assert.same({}, g.edges)
    assert.same({}, g.subgraphs)
    assert.is_true(model.validate(g))
  end)

  it("adds nodes with defaults", function()
    local g = model.new("LR")
    model.add_node(g, "A")
    model.add_node(g, "B", "Bee", "rect")
    assert.same({ id = "A", label = "A", shape = "rect" }, g.nodes[1])
    assert.equals("Bee", g.nodes[2].label)
    assert.is_true(model.validate(g))
  end)

  it("redeclaration keeps the node and replaces a given label", function()
    local g = model.new()
    model.add_node(g, "A", "one")
    model.add_node(g, "A")
    assert.equals("one", g.nodes[1].label)
    model.add_node(g, "A", "two")
    assert.equals(1, #g.nodes)
    assert.equals("two", g.nodes[1].label)
  end)

  it("validate rejects bad graphs", function()
    local ok, err = model.validate(nil)
    assert.is_false(ok)
    assert.is_string(err)
    assert.is_false(model.validate({ direction = "XX", nodes = {}, edges = {}, subgraphs = {} }))
    assert.is_false(model.validate({ direction = "TD", nodes = {}, subgraphs = {} }))
    local g = model.new()
    g.nodes[1] = { id = "A", label = "A" }
    assert.is_false(model.validate(g))
    g.nodes[1] = { id = "A", label = "A", shape = "rect" }
    g.nodes[2] = { id = "A", label = "A", shape = "rect" }
    assert.is_false(model.validate(g))
    g.nodes = { { id = "", label = "", shape = "rect" } }
    assert.is_false(model.validate(g))
  end)

  it("adds edges with defaults and validates them", function()
    local g = model.new()
    model.add_node(g, "A")
    model.add_node(g, "B")
    local e = model.add_edge(g, "A", "B")
    assert.same(
      { from = "A", to = "B", style = "solid", head = "arrow", tail = "none", length = 1 },
      e
    )
    assert.is_true(model.validate(g))
    e.style = "wavy"
    assert.is_false(model.validate(g))
    e.style = "solid"
    e.to = "Z"
    assert.is_false(model.validate(g))
  end)

  it("a later shape replaces the earlier one, an omitted shape keeps it", function()
    local g = model.new()
    model.add_node(g, "A")
    model.add_node(g, "A", nil, "round")
    model.add_node(g, "A")
    assert.equals("round", g.nodes[1].shape)
  end)
end)
