local mermaid = require("doc_preview.mermaid")
local out = require("doc_preview.core.out")
local registry = require("doc_preview.mermaid.registry")
local text = require("doc_preview.core.text")

local ctx = { width = 40 }

local function check_width(o, width)
  for _, l in ipairs(o.lines) do
    assert.is_true(text.width(l) <= width, l)
  end
end

local function title_of(o)
  return o.lines[2]
end

describe("mermaid.detect", function()
  it("takes the first word", function()
    assert.equals("flowchart", mermaid.detect({ "flowchart TD", "A-->B" }))
    assert.equals("graph", mermaid.detect({ "graph LR;" }))
    assert.equals("sequenceDiagram", mermaid.detect({ "sequenceDiagram" }))
    assert.equals("stateDiagram-v2", mermaid.detect({ "stateDiagram-v2" }))
  end)

  it("is case-sensitive", function()
    assert.equals("Flowchart", mermaid.detect({ "Flowchart TD" }))
  end)

  it("skips blanks and comments", function()
    assert.equals("pie", mermaid.detect({ "", "  ", "%% note", "  %% more", "pie" }))
  end)

  it("skips single and multi-line directives", function()
    assert.equals("gantt", mermaid.detect({ "%%{init: {}}%%", "gantt" }))
    assert.equals("gantt", mermaid.detect({ "%%{", "init: {}", "}%%", "gantt" }))
  end)

  it("skips frontmatter", function()
    assert.equals("classDiagram", mermaid.detect({ "---", "title: x", "---", "classDiagram" }))
    assert.equals("pie", mermaid.detect({ "", "---", "---", "%% c", "pie" }))
  end)

  it("returns nil without content", function()
    assert.is_nil(mermaid.detect({}))
    assert.is_nil(mermaid.detect({ "", "%% only a comment", "%%{init}%%" }))
    assert.is_nil(mermaid.detect({ "---", "title: x", "---" }))
  end)
end)

describe("mermaid.render", function()
  after_each(function()
    registry.unregister("fake")
  end)

  it("boxes an unknown type with its name", function()
    local o = mermaid.render({ "mindmap", "  title x" }, { width = 60 })
    assert.equals('│ mermaid: unsupported diagram type "mindmap" │', title_of(o))
    assert.equals(1, #o.map)
    assert.equals(2, o.map[1].src_end)
    check_width(o, 60)
  end)

  it("gives an errbox for empty source", function()
    for _, src in ipairs({ {}, { "" }, { "%% c" } }) do
      local o = mermaid.render(src, ctx)
      assert.is_truthy(title_of(o):find("empty diagram", 1, true))
    end
  end)

  it("returns the module output", function()
    registry.register("fake", {
      render = function()
        local o = out.new()
        o:add_line("ok")
        return o
      end,
    })
    assert.same({ "ok" }, mermaid.render({ "%% c", "fake x" }, ctx).lines)
  end)

  it("passes lines and ctx to the module", function()
    local seen
    registry.register("fake", {
      render = function(lines, c)
        seen = { lines, c }
        return out.new()
      end,
    })
    local src = { "fake" }
    mermaid.render(src, ctx)
    assert.equals(src, seen[1])
    assert.equals(ctx, seen[2])
  end)

  it("catches a raising module", function()
    registry.register("fake", {
      render = function()
        error("boom")
      end,
    })
    local o = mermaid.render({ "fake" }, { width = 80 })
    assert.is_truthy(title_of(o):find("fake: ", 1, true))
    assert.is_truthy(title_of(o):find("boom", 1, true))
    assert.is_truthy(o.lines[4]:find("fake", 1, true))
    check_width(o, 80)
  end)

  it("replaces garbage output", function()
    local garbage = { 42, "str", {}, { lines = { 1 }, spans = {}, map = {} } }
    for _, g in ipairs(garbage) do
      registry.register("fake", {
        render = function()
          return g
        end,
      })
      local o = mermaid.render({ "fake" }, ctx)
      assert.is_truthy(title_of(o):find("invalid output", 1, true))
    end
  end)

  it("replaces output wider than the width", function()
    registry.register("fake", {
      render = function()
        local o = out.new()
        o:add_line(("x"):rep(50))
        return o
      end,
    })
    local o = mermaid.render({ "fake" }, ctx)
    assert.is_truthy(title_of(o):find("invalid output", 1, true))
    check_width(o, ctx.width)
  end)

  it("never exceeds the width, even tiny", function()
    for _, w in ipairs({ 1, 3, 10, 20 }) do
      local o = mermaid.render({ "unknownType with a very long line of text" }, { width = w })
      check_width(o, w)
    end
  end)
end)
