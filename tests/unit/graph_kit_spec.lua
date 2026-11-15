local draw = require("doc_preview.graph.draw")
local ends = require("doc_preview.graph.ends")
local layout = require("doc_preview.graph.layout")
local model = require("doc_preview.graph.model")
local shapes = require("doc_preview.graph.shapes")

local function render(g, ctx)
  ctx = ctx or { width = 80 }
  local fitted = draw.fit(g, ctx.width)
  local lay = layout.layout(fitted)
  return draw.draw(fitted, lay, ctx).lines, lay
end

local function record(g, id, title, rows)
  return model.add_node(g, id, title, "record", rows)
end

local function pair(dir, opts, rows_a)
  local g = model.new(dir)
  record(g, "A", "Animal", rows_a or { { "+name", "+age" }, { "+eat()" } })
  record(g, "B", "Dog", { { "+bark()" } })
  model.add_edge(g, "B", "A", opts)
  return g
end

describe("graph.model record fields", function()
  it("old graphs stay valid and carry no new fields", function()
    local g = model.new()
    model.add_node(g, "A")
    model.add_node(g, "B")
    local e = model.add_edge(g, "A", "B")
    assert.is_true(model.validate(g))
    assert.is_nil(e.head_kind)
    assert.is_nil(g.by_id.A.rows)
  end)

  it("validates rows, kinds and end labels", function()
    local g = pair(
      "TD",
      { head_kind = "diamond_filled", tail_kind = "triangle", head_label = "1", tail_label = "*" }
    )
    assert.is_true(model.validate(g))
    g.edges[1].head_kind = "bogus"
    assert.is_false(model.validate(g))
    g.edges[1].head_kind = nil
    g.edges[1].tail_label = 3
    assert.is_false(model.validate(g))
    g.edges[1].tail_label = nil
    g.nodes[1].rows = { { 1 } }
    assert.is_false(model.validate(g))
  end)
end)

describe("graph.shapes record", function()
  it("sizes from the widest line and the row count", function()
    local g = model.new()
    local n = record(g, "A", "Animal", { { "+name", "+age" }, { "+eat()" } })
    local w, h = shapes.size(n)
    assert.equals(10, w)
    assert.equals(8, h) -- 2 borders, 1 title, 3 rows, 2 dividers
  end)

  it("draws one section", function()
    local g = model.new()
    record(g, "A", "Cat", { { "+purr()" } })
    assert.same({
      "┌─────────┐",
      "│   Cat   │",
      "├─────────┤",
      "│ +purr() │",
      "└─────────┘",
    }, render(g))
  end)

  it("draws several sections and skips empty ones", function()
    local g = model.new()
    record(g, "A", "Cat", { { "+a", "+b" }, {}, { "+c()" } })
    assert.same({
      "┌──────┐",
      "│ Cat  │",
      "├──────┤",
      "│ +a   │",
      "│ +b   │",
      "├──────┤",
      "│ +c() │",
      "└──────┘",
    }, render(g))
  end)

  it("draws ascii dividers", function()
    local g = model.new()
    record(g, "A", "Cat", { { "+x" } })
    local lines = render(g, { width = 80, charset = "ascii" })
    assert.same({ "+-----+", "| Cat |", "+-----+", "| +x  |", "+-----+" }, lines)
  end)

  it("measures wide glyphs by display width", function()
    local g = model.new()
    record(g, "A", "T", { { "漢字" } })
    assert.same({
      "┌──────┐",
      "│  T   │",
      "├──────┤",
      "│ 漢字 │",
      "└──────┘",
    }, render(g))
  end)

  it("cuts a line wider than the width with ...", function()
    local g = model.new()
    record(g, "A", "T", { { "+a_very_long_member_name" } })
    local lines = render(g, { width = 12 })
    assert.same({
      "┌──────────┐",
      "│    T     │",
      "├──────────┤",
      "│ +a_ve... │",
      "└──────────┘",
    }, lines)
  end)
end)

describe("graph.layout mixed heights", function()
  local function overlap(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
  end

  for _, dir in ipairs({ "TD", "LR" }) do
    it("keeps boxes apart and sized by shape on " .. dir, function()
      local g = pair(dir)
      model.add_node(g, "C", "C")
      model.add_edge(g, "C", "A")
      local _, lay = render(g)
      assert.equals(8, lay.nodes.A.h)
      assert.equals(5, lay.nodes.B.h)
      assert.equals(3, lay.nodes.C.h)
      for _, a in pairs(lay.nodes) do
        for _, b in pairs(lay.nodes) do
          assert.is_true(a == b or not overlap(a, b))
        end
      end
    end)
  end
end)

describe("graph.ends", function()
  it("has glyphs per kind and direction", function()
    assert.equals("▽", ends.glyph("triangle", "down", "unicode"))
    assert.equals("▷", ends.glyph("triangle", "right", "unicode"))
    assert.equals("◆", ends.glyph("diamond_filled", "up", "unicode"))
    assert.equals("◇", ends.glyph("diamond", "up", "unicode"))
    assert.equals("*", ends.glyph("diamond_filled", "up", "ascii"))
    assert.equals("<", ends.glyph("open", "left", "ascii"))
    assert.is_nil(ends.glyph("none", "up", "unicode"))
  end)

  it("draws end glyphs and labels on TD", function()
    local g = pair(
      "TD",
      { head_kind = "triangle", tail_kind = "diamond", head_label = "1", tail_label = "0..*" }
    )
    local lines = render(g)
    assert.same({ "     ◇ 0..*", "     │", "     ▽ 1" }, { lines[6], lines[7], lines[8] })
  end)

  it("draws end glyphs and labels on LR", function()
    local g = pair("LR", {
      head_kind = "triangle",
      tail_kind = "diamond_filled",
      head_label = "1",
      tail_label = "0..*",
    })
    local lines = render(g)
    assert.equals("│   Dog   │0..*   1│ +name  │", lines[4])
    assert.equals(
      "├─────────┤◆──────▷│ +age   │",
      lines[5]
    )
  end)

  it("draws ascii forms", function()
    local g = pair("TD", { head_kind = "open", tail_kind = "diamond_filled", head_label = "1" })
    local lines = render(g, { width = 80, charset = "ascii" })
    assert.same({ "     *", "     |", "     v 1" }, { lines[6], lines[7], lines[8] })
  end)

  it("never draws an end label over a border", function()
    local g = pair("TD", { head_label = "a label that is far too long to sit beside" })
    local lines = render(g)
    for _, l in ipairs(lines) do
      assert.is_nil(l:find("┌[^─┐]"))
    end
  end)

  it("plain edges keep head and tail", function()
    local g = pair("TD", { head = "circle", tail = "cross" })
    local lines = render(g)
    assert.equals("     x", lines[6])
    assert.equals("     o", lines[8])
  end)
end)
