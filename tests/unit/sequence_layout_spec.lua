local draw = require("doc_preview.mermaid.sequence_draw")
local layout = require("doc_preview.mermaid.sequence_layout")
local mermaid = require("doc_preview.mermaid")
local sequence = require("doc_preview.mermaid.sequence")
local text = require("doc_preview.core.text")

local function lay(src, opts)
  local lines = { "sequenceDiagram" }
  vim.list_extend(lines, vim.split(src, "\n"))
  return layout.layout(sequence.parse(lines), opts), lines
end

local function rendered(src, width, charset)
  local lines = { "sequenceDiagram" }
  vim.list_extend(lines, vim.split(src, "\n"))
  return mermaid.render(lines, { width = width or 80, charset = charset })
end

-- Character at 0-based display column x of a line.
local function at(line, x)
  return vim.fn.strcharpart(line, x, 1)
end

local function message(l, n)
  local k = 0
  for _, item in ipairs(l.items) do
    if item.kind == "message" then
      k = k + 1
      if k == n then
        return item
      end
    end
  end
end

describe("sequence layout columns", function()
  it("orders columns left to right with room for the boxes", function()
    local l = lay("participant A as Alice\nB->>A: hi")
    assert.equals(2, #l.cols)
    assert.is_true(l.cols[1].x < l.cols[2].x)
    assert.is_true(l.cols[1].x + l.cols[1].hr < l.cols[2].x - l.cols[2].hl)
  end)

  it("widens the span for a long message text", function()
    local short = lay("A->>B: x")
    local long = lay("A->>B: a longer message text")
    assert.is_true(long.cols[2].x - long.cols[1].x >= text.width("a longer message text") + 3)
    assert.is_true(long.width > short.width)
  end)

  it("uses less room in compact mode", function()
    local normal = lay("A->>B: x")
    local compact = lay("A->>B: x", { compact = true })
    assert.is_true(compact.width < normal.width)
  end)

  it("a message across a column spans both ends", function()
    local l = lay("A->>C: a text\nB->>B: z")
    assert.is_true(l.cols[3].x - l.cols[1].x >= text.width("a text") + 3)
  end)

  it("keeps a source line per item", function()
    local l = lay("A->>B: x\nNote over A: n")
    assert.equals(2, l.items[1].src)
    assert.equals(3, l.items[2].src)
  end)
end)

describe("sequence layout rows", function()
  it("puts events in source order, one row group each", function()
    local l = lay("A->>B: one\nB->>A: two")
    local a, b = message(l, 1), message(l, 2)
    assert.is_true(a.y < b.y)
    assert.is_true(l.height > b.y + l.boxh)
  end)

  it("gives wrapped text one row per line above the arrow", function()
    local l = lay("A->>B: a b c d e f", { wrap = 3 })
    assert.equals(3, #message(l, 1).lines)
  end)

  it("makes a self-message two rows tall", function()
    local l = lay("A->>A: me\nA->>A: again")
    assert.equals(2 + 1 + 1 + 1, message(l, 2).y - message(l, 1).y + 1 + 1 - 1 + 1 - 1)
  end)

  it("records activation bars from shorthand and statements", function()
    local l = lay("A->>+B: go\nB-->>-A: back\nactivate A\ndeactivate A")
    assert.equals(2, #l.bars)
    assert.equals(2, l.bars[1].col)
    assert.equals(message(l, 1).y, l.bars[1].y0)
    assert.equals(message(l, 2).y, l.bars[1].y1)
  end)

  it("closes an activation left open at the end", function()
    local l = lay("A->>+B: go")
    assert.equals(1, #l.bars)
    assert.equals(l.life.y0 + l.life.len - 1, l.bars[1].y1)
  end)

  it("records frames with dividers and nesting depth", function()
    local l = lay("loop L\nalt a\nA->>B: x\nelse b\nB->>A: y\nend\nend")
    assert.equals(2, #l.frames)
    local inner, outer = l.frames[1], l.frames[2]
    assert.equals(1, inner.depth)
    assert.equals(0, outer.depth)
    assert.equals(1, #inner.dividers)
    assert.is_true(outer.y0 < inner.y0 and inner.y1 < outer.y1)
  end)

  it("treats rect as transparent", function()
    local l = lay("rect rgb(1,2,3)\nA->>B: x\nend")
    assert.equals(0, #l.frames)
    assert.equals(1, #l.items)
  end)

  it("numbers messages with autonumber, start and step", function()
    local l = lay("autonumber 10 5\nA->>B: x\nB->>A: y\nautonumber off\nA->>B: z")
    assert.same({ "10. x" }, message(l, 1).lines)
    assert.same({ "15. y" }, message(l, 2).lines)
    assert.same({ "z" }, message(l, 3).lines)
  end)
end)

describe("sequence drawing", function()
  it("draws boxes at the top and bottom with the labels", function()
    local o = rendered("participant A as Alice\nA->>B: hi")
    assert.equals(o.lines[2], o.lines[#o.lines - 1])
    assert.matches("│ Alice │", o.lines[2], 1, true)
  end)

  it("uses rounded corners for actors and plain boxes in ascii", function()
    assert.matches("╭", rendered("actor A\nA->>B: x").lines[1])
    assert.matches("%+%-%-%-%+", rendered("actor A\nA->>B: x", 80, "ascii").lines[1])
  end)

  it("connects the right lifelines with heads next to the target", function()
    local src = "participant A\nparticipant B\nparticipant C\nA->>C: go\nC-->>A: back"
    local l = lay(src)
    local o = rendered(src)
    local m1, m2 = message(l, 1), message(l, 2)
    local xa, xc = l.cols[1].x, l.cols[3].x
    local r1, r2 = o.lines[m1.y + 1], o.lines[m2.y + 1]
    assert.equals("─", at(r1, xa + 1))
    assert.equals("▶", at(r1, xc - 1))
    assert.equals("◀", at(r2, xa + 1))
    assert.equals("┄", at(r2, xc - 1))
    assert.equals("┼", at(r1, l.cols[2].x))
  end)

  it("draws the head kinds", function()
    local src = "A->>B: a\nA->B: b\nA-xB: c\nA-)B: d"
    local l = lay(src)
    local o = rendered(src)
    local heads = {}
    for n = 1, 4 do
      heads[n] = at(o.lines[message(l, n).y + 1], l.cols[2].x - 1)
    end
    assert.same({ "▶", "─", "x", ")" }, heads)
  end)

  it("draws a self-message loop", function()
    local o = rendered("A->>A: me")
    local text_ = table.concat(o.lines, "\n")
    assert.matches("├──┐", text_, 1, true)
    assert.matches("◀─┘", text_, 1, true)
  end)

  it("draws activation bars on the lifeline", function()
    local o = rendered("A->>+B: go\nB-->>-A: back")
    assert.matches("┃", table.concat(o.lines, "\n"), 1, true)
  end)

  it("draws frames with labels and else dividers", function()
    local s = table.concat(rendered("alt ok\nA->>B: x\nelse bad\nB->>A: y\nend").lines, "\n")
    assert.matches("┌─ [alt] ok", s, 1, true)
    assert.matches("┄ [else] bad", s, 1, true)
    assert.matches("└", s, 1, true)
  end)

  it("keeps notes inside their own box without overlapping lifeline arrows", function()
    local l = lay("A->>B: x\nNote right of B: hello")
    local note = l.items[2]
    assert.is_true(note.x > l.cols[2].x)
    local o = rendered("A->>B: x\nNote right of B: hello")
    assert.matches("│ hello │", o.lines[note.y + 2], 1, true)
  end)

  it("adds highlight spans", function()
    local groups = {}
    for _, s in ipairs(rendered("A->>B: x").spans) do
      groups[s.hl_group] = true
    end
    assert.is_true(
      groups.DocPreviewDiagramBorder
        and groups.DocPreviewDiagramLabel
        and groups.DocPreviewDiagramEdge
    )
  end)
end)

describe("sequence width policy", function()
  local wide = "Client->>Server: a very long message text that has to wrap\nServer->>Db: q"

  local function max_width(o)
    local w = 0
    for _, l in ipairs(o.lines) do
      w = math.max(w, text.width(l))
    end
    return w
  end

  it("never exceeds the width, at any width", function()
    for width = 1, 90 do
      assert.is_true(max_width(rendered(wide, width)) <= width, "width " .. width)
      local blocks =
        rendered("loop a long label here\nA->>B: x\nNote over A,B: some text\nend", width)
      assert.is_true(max_width(blocks) <= width, "blocks width " .. width)
    end
  end)

  it("wraps message text before giving up", function()
    local o = rendered(wide, 40)
    assert.is_nil(o.lines[1]:find("wider than", 1, true))
    assert.matches("┌", o.lines[1])
    assert.is_true(#o.lines > 12)
  end)

  it("falls back to the boxed source with a note", function()
    local o =
      rendered("A->>B: 1\nB->>C: 2\nC->>D: 3\nD->>E: 4\nE->>F: 5\nF->>G: 6\nG->>H: 7\nH->>I: 8", 40)
    assert.matches("diagram wider than 40 columns", o.lines[2])
    assert.matches("sequenceDiagram", table.concat(o.lines, "\n"))
  end)

  it("uses compact spacing before wrapping", function()
    local normal = lay("participant A\nparticipant B\nA->>B: x")
    local o = rendered("participant A\nparticipant B\nA->>B: x", normal.width - 1)
    assert.matches("x", table.concat(o.lines, "\n"))
    assert.is_true(max_width(o) < normal.width)
  end)

  it("draws something at tiny widths without raising", function()
    assert.is_true(max_width(rendered("A->>B: hi", 3)) <= 3)
  end)

  it("errors on a diagram without participants", function()
    local o = mermaid.render({ "sequenceDiagram" }, { width = 40 })
    assert.matches("no partici", table.concat(o.lines, "\n"))
  end)
end)

describe("sequence draw module", function()
  it("is syntax free: draws a hand-built layout input", function()
    local model = require("doc_preview.mermaid.sequence_model")
    local seq = model.new()
    model.add_participant(seq, "x", "X")
    model.add_participant(seq, "y", "Y")
    model.add_event(seq.events, {
      kind = "message",
      from = "x",
      to = "y",
      text = "t",
      line = "solid",
      head = "arrow",
      src = 1,
    })
    local o = draw.draw(layout.layout(seq), { width = 40 })
    assert.matches("▶", table.concat(o.lines, "\n"), 1, true)
  end)
end)
