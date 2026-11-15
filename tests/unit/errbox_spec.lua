local errbox = require("doc_preview.core.errbox")
local text = require("doc_preview.core.text")

local function check_width(o, width)
  for _, l in ipairs(o.lines) do
    assert.is_true(text.width(l) <= width, l)
  end
end

describe("core.errbox", function()
  it("boxes title and source", function()
    local o = errbox.render({ "gantt", "  a" }, { width = 40 }, "unsupported")
    assert.same({
      "┌─────────────┐",
      "│ unsupported │",
      "├─────────────┤",
      "│ gantt       │",
      "│   a         │",
      "└─────────────┘",
    }, o.lines)
  end)

  it("has one map entry over the whole block", function()
    local o = errbox.render({ "a", "b", "c" }, { width = 20 }, "t")
    assert.same({ { out_start = 1, out_end = #o.lines, src_start = 1, src_end = 3 } }, o.map)
  end)

  it("wraps long lines to the width", function()
    local o = errbox.render({ ("x"):rep(50) }, { width = 20 }, "title")
    check_width(o, 20)
    assert.equals(20, text.width(o.lines[1]))
    assert.is_true(#o.lines > 5)
  end)

  it("handles width 1 without exceeding it", function()
    local o = errbox.render({ "abc", "" }, { width = 1 }, "ab")
    check_width(o, 1)
    assert.is_true(#o.lines >= 5)
  end)

  it("handles widths too small for a box", function()
    for w = 1, 5 do
      check_width(errbox.render({ "abcdefgh" }, { width = w }, "title"), w)
    end
  end)

  it("handles empty source", function()
    local o = errbox.render({}, { width = 30 }, "empty")
    assert.same(
      { "┌───────┐", "│ empty │", "└───────┘" },
      o.lines
    )
    assert.same({ { out_start = 1, out_end = 3, src_start = 1, src_end = 1 } }, o.map)
  end)

  it("uses the ascii charset", function()
    local o = errbox.render({ "a" }, { width = 30, charset = "ascii" }, "t")
    assert.same({ "+---+", "| t |", "+---+", "| a |", "+---+" }, o.lines)
  end)

  it("expands tabs and wraps wide chars within the width", function()
    local o = errbox.render({ "\ta", "漢字漢字漢字" }, { width = 10 }, "t")
    check_width(o, 10)
  end)

  it("styles borders and text with spans in byte columns", function()
    local o = errbox.render({ "é" }, { width = 30 }, "t")
    local row = 4
    local by = {}
    for _, s in ipairs(o.spans) do
      if s.line == row then
        by[#by + 1] = s
      end
    end
    assert.equals("DocPreviewDiagramBorder", by[1].hl_group)
    assert.equals("DocPreviewErrbox", by[2].hl_group)
    assert.equals(o.lines[row]:sub(by[2].col_start + 1, by[2].col_end), "é")
    assert.equals(#o.lines[row], by[3].col_end)
  end)
end)
