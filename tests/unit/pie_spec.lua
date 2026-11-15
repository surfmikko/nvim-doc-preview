local mermaid = require("doc_preview.mermaid")
local pie = require("doc_preview.mermaid.pie")
local text = require("doc_preview.core.text")

local function parse(...)
  return pie.parse({ "pie", ... })
end

local function pcts(p)
  local r = {}
  for i, s in ipairs(p.slices) do
    r[i] = s.pct
  end
  return r
end

local function render(width, lines, charset)
  return mermaid.render(lines, { width = width, charset = charset }).lines
end

describe("pie.parse", function()
  it("reads header options, title and slices", function()
    local p = pie.parse({ "pie showData title A: b", '"x" : 1.5', '  "y z" : 0;' })
    assert.is_true(p.show_data)
    assert.equals("A: b", p.title)
    assert.equals("y z", p.slices[2].label)
    assert.equals(0, p.slices[2].value)
  end)

  it("accepts title and showData on their own lines", function()
    local p = parse("showData", "title T", '"a" : 1')
    assert.is_true(p.show_data)
    assert.equals("T", p.title)
  end)

  it("names the line of an error", function()
    assert.has_error(function()
      parse('"a" : -1')
    end, "line 2: negative value -1")
    assert.has_error(function()
      parse('"a" : x')
    end, "line 2: invalid value x")
    assert.has_error(function()
      parse("a : 1")
    end, "line 2: syntax error: a : 1")
    assert.has_error(function()
      pie.parse({ "pies" })
    end, "line 1: expected pie")
  end)

  it("rounds percentages by largest remainder to 100", function()
    assert.same({ 34, 33, 33 }, pcts(parse('"a":1', '"b":1', '"c":1')))
    assert.same({ 100 }, pcts(parse('"a":7')))
    assert.same({ 0, 100 }, pcts(parse('"a":0', '"b":2')))
    assert.same({ 0 }, pcts(parse('"a":0')))
    assert.same({}, pcts(parse()))
    local sum = 0
    for _, v in ipairs(pcts(parse('"a":1', '"b":2', '"c":4', '"d":8', '"e":16', '"f":32'))) do
      sum = sum + v
    end
    assert.equals(100, sum)
  end)
end)

describe("pie render", function()
  it("draws a title and one bar per slice in source order", function()
    local lines = render(40, { "pie title T", '"Dogs" : 3', '"Cats" : 1' })
    assert.equals("T", lines[1])
    assert.truthy(lines[2]:match("^Dogs █+.* 75%%$"))
    assert.truthy(lines[3]:match("^Cats █+.* 25%%$"))
  end)

  it("shows raw values only with showData", function()
    assert.falsy(render(40, { "pie", '"a" : 1.50' })[1]:find("1.50", 1, true))
    assert.truthy(render(40, { "pie showData", '"a" : 1.50' })[1]:find("1.50", 1, true))
  end)

  it("fills the bar for a single slice and leaves a zero slice empty", function()
    local lines = render(40, { "pie", '"a" : 5', '"b" : 0' })
    assert.truthy(lines[1]:find(("█"):rep(30), 1, true))
    assert.falsy(lines[2]:find("█", 1, true))
  end)

  it("uses # in the ascii charset", function()
    local l = render(40, { "pie", '"a" : 1' }, "ascii")[1]
    assert.truthy(l:find(("#"):rep(30), 1, true))
    assert.falsy(l:find("█", 1, true))
  end)

  it("cuts wide labels with ... and never exceeds the width", function()
    local src = {
      "pie showData",
      '"漢字漢字漢字漢字漢字漢字漢字" : 3',
      '"long label here" : 12345678',
    }
    for width = 12, 60 do
      for _, l in ipairs(render(width, src)) do
        assert.is_true(text.width(l) <= width, width .. ": " .. l)
      end
    end
    assert.truthy(render(30, src)[1]:find("...", 1, true))
  end)

  it("boxes the source with a note when nothing fits", function()
    local lines = render(24, { "pie showData", '"label" : 1234567' })
    assert.truthy(table.concat(lines, "\n"):find("diagram wider", 1, true))
  end)

  it("gives an errbox for an empty pie and a bad value", function()
    assert.truthy(table.concat(render(40, { "pie" }), "\n"):find("no slices", 1, true))
    assert.truthy(table.concat(render(40, { "pie", '"a" : -2' }), "\n"):find("negative", 1, true))
  end)
end)
