local mermaid = require("doc_preview.mermaid")
local sequence = require("doc_preview.mermaid.sequence")
local syntax = require("doc_preview.mermaid.sequence_syntax")

local function parse(...)
  return sequence.parse({ "sequenceDiagram", ... })
end

local function fails(...)
  local ok, err = pcall(parse, ...)
  assert.is_false(ok)
  return err
end

describe("sequence.parse participants", function()
  it("reads declarations, aliases and implicit participants in order", function()
    local s = parse("participant A as Alice", "actor B", "C->>A: hi")
    assert.same(
      { "A", "B", "C" },
      vim.tbl_map(function(p)
        return p.id
      end, s.participants)
    )
    assert.equals("Alice", s.by_id.A.label)
    assert.equals("actor", s.by_id.B.kind)
    assert.equals("participant", s.by_id.C.kind)
  end)

  it("keeps the declaration order when a mention came first", function()
    local s = parse("B->>A: x", "participant A as Ann")
    assert.equals("B", s.participants[1].id)
    assert.equals("Ann", s.by_id.A.label)
  end)

  it("keeps source line numbers", function()
    local s = parse("participant A", "A->>B: x")
    assert.equals(2, s.by_id.A.src)
    assert.equals(3, s.events[1].src)
  end)
end)

describe("sequence.parse messages", function()
  local cases = {
    { "->", "solid", "open" },
    { "-->", "dashed", "open" },
    { "->>", "solid", "arrow" },
    { "-->>", "dashed", "arrow" },
    { "-x", "solid", "cross" },
    { "--x", "dashed", "cross" },
    { "-)", "solid", "async" },
    { "--)", "dashed", "async" },
  }
  for _, c in ipairs(cases) do
    it("maps " .. c[1], function()
      local e = parse("A" .. c[1] .. "B: t").events[1]
      assert.same({ c[2], c[3], "A", "B", "t" }, { e.line, e.head, e.from, e.to, e.text })
    end)
  end

  it("allows spaces, a missing text and <br/>", function()
    local s = parse("A ->> B : x<br/>y", "A->>B")
    assert.equals("x\ny", s.events[1].text)
    assert.equals("", s.events[2].text)
  end)

  it("reads the activation shorthand", function()
    local e = parse("A->>+B: x", "B-->>-A: y").events
    assert.is_true(e[1].activate)
    assert.is_nil(e[1].deactivate)
    assert.is_true(e[2].deactivate)
  end)

  it("splits statements on semicolons", function()
    assert.equals(2, #parse("A->>B: x; B->>A: y").events)
  end)
end)

describe("sequence.parse notes, activation, autonumber", function()
  it("reads notes", function()
    local n = parse("Note over A,B: both", "note left of C: l").events
    assert.same({ "over", { "A", "B" }, "both" }, { n[1].side, n[1].targets, n[1].text })
    assert.same({ "left", { "C" } }, { n[2].side, n[2].targets })
  end)

  it("reads activate and deactivate", function()
    local e = parse("activate A", "deactivate A").events
    assert.same({ "activate", "A" }, { e[1].kind, e[1].id })
    assert.equals("deactivate", e[2].kind)
  end)

  it("reads autonumber variants", function()
    local e = parse("autonumber", "autonumber 10 5", "autonumber off").events
    assert.is_nil(e[1].start)
    assert.same({ 10, 5 }, { e[2].start, e[2].step })
    assert.is_true(e[3].off)
  end)
end)

describe("sequence.parse blocks", function()
  it("nests blocks and splits sections", function()
    local s = parse("loop L", "alt a", "A->>B: x", "else b", "B->>A: y", "end", "end")
    local loop = s.events[1]
    assert.equals("loop", loop.type)
    local alt = loop.sections[1].events[1]
    assert.same({ "alt", "a" }, { alt.type, alt.label })
    assert.equals(2, #alt.sections)
    assert.equals("b", alt.sections[2].label)
    assert.equals("y", alt.sections[2].events[1].text)
  end)

  it("accepts and/option for par/critical", function()
    local s = parse("par a", "and b", "end", "critical c", "option d", "end")
    assert.equals(2, #s.events[1].sections)
    assert.equals(2, #s.events[2].sections)
  end)

  it("errors name the line", function()
    assert.matches("line 3: loop is not closed", fails("A->>B: x", "loop x"))
    assert.matches("line 2: end without block", fails("end"))
    assert.matches("line 3: else outside alt", fails("loop x", "else y"))
    assert.matches("line 2: syntax error: nonsense", fails("nonsense"))
  end)

  it("ignores box and unrelated statements", function()
    local s = parse("title T", "box Team", "participant A", "end", "link A: x")
    assert.equals(0, #s.events)
    assert.equals(1, #s.participants)
  end)
end)

describe("sequence.parse robustness", function()
  it("skips frontmatter, directives and comments", function()
    local s = sequence.parse({
      "---",
      "title: t",
      "---",
      "%%{init: {}}%%",
      "sequenceDiagram",
      "%% c",
      "A->>B: x",
    })
    assert.equals(1, #s.events)
  end)

  it("never throws anything but a string on garbage", function()
    local garbage = {
      "",
      ";;",
      "->",
      "A->>",
      "Note",
      "Note over",
      "end end",
      "loop",
      "participant",
      "autonumber x y",
      "\0",
    }
    for _, g in ipairs(garbage) do
      local ok, err = pcall(parse, g, g)
      assert.is_true(ok or type(err) == "string", g)
    end
  end)

  it("exposes the message parser for single statements", function()
    assert.is_nil(syntax.message("hello"))
  end)
end)

describe("mermaid registry", function()
  it("registers sequenceDiagram and reports parse errors in an errbox", function()
    local o = mermaid.render({ "sequenceDiagram", "nonsense" }, { width = 60 })
    assert.matches("line 2: syntax error", table.concat(o.lines, "\n"))
  end)

  it("draws a valid diagram within the width", function()
    local o = mermaid.render({ "sequenceDiagram", "A->>B: hi" }, { width = 30 })
    assert.matches("hi", table.concat(o.lines, "\n"))
    for _, l in ipairs(o.lines) do
      assert.is_true(vim.fn.strdisplaywidth(l) <= 30, l)
    end
  end)
end)
