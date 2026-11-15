local text = require("doc_preview.core.text")

local function assert_fits(lines, width)
  for _, l in ipairs(lines) do
    assert.is_true(text.width(l) <= width, l)
  end
end

describe("core.text", function()
  it("measures display width", function()
    assert.equals(3, text.width("abc"))
    assert.equals(4, text.width("日本"))
    assert.equals(0, text.width(""))
  end)

  it("wraps ASCII greedily on spaces", function()
    assert.same({ "aaa bbb", "ccc" }, text.wrap("aaa bbb ccc", 7))
    assert.same({ "aaa", "bbb", "ccc" }, text.wrap("aaa bbb ccc", 6))
  end)

  it("collapses whitespace and newlines", function()
    assert.same({ "a b c" }, text.wrap("a \n  b\t\tc\n", 10))
  end)

  it("returns no lines for empty input", function()
    assert.same({}, text.wrap("", 10))
    assert.same({}, text.wrap("  \n ", 10))
  end)

  it("hard-splits long words", function()
    local lines = text.wrap("abcdefghij", 4)
    assert.same({ "abcd", "efgh", "ij" }, lines)
    assert.same({ "ab", "cd", "ef" }, text.wrap("abcdef", 2))
  end)

  it("continues a hard-split word's tail with the next word", function()
    assert.same({ "abcd", "ef g" }, text.wrap("abcdef g", 4))
  end)

  it("never splits a wide char", function()
    local lines = text.wrap("日本語テキスト", 5)
    assert.same({ "日本", "語テ", "キス", "ト" }, lines)
    assert_fits(lines, 5)
    assert.same({ "a", "日", "b" }, text.wrap("a日b", 2))
  end)

  it("wraps emoji at the boundary", function()
    local lines = text.wrap("ab 😀😀😀", 5)
    assert.same({ "ab", "😀😀", "😀" }, lines)
    assert_fits(lines, 5)
  end)

  it("treats width < 1 as 1", function()
    assert.same({ "a", "b" }, text.wrap("ab", 0))
    assert.same({ "a", "b" }, text.wrap("a b", -3))
  end)

  it("pads by display width", function()
    assert.equals("ab   ", text.pad("ab", 5))
    assert.equals("   ab", text.pad("ab", 5, "right"))
    assert.equals(" ab  ", text.pad("ab", 5, "center"))
    assert.equals("日本 ", text.pad("日本", 5))
    assert.equals("abcdef", text.pad("abcdef", 3))
  end)
end)

describe("core.text wrap_styled", function()
  it("gives the same lines as wrap when there are no ranges", function()
    local s = "aaa bbb ccc ddddddddddd ee"
    for width = 1, 12 do
      local lines = text.wrap_styled(s, width, {})
      assert.same(text.wrap(s, width), lines)
    end
  end)

  it("keeps a range on one line", function()
    local lines, spans = text.wrap_styled("aa bb cc", 20, { { from = 3, to = 5, group = "G" } })
    assert.same({ "aa bb cc" }, lines)
    assert.same({ { line = 1, col_start = 3, col_end = 5, hl_group = "G" } }, spans)
  end)

  it("splits a range that wraps over two lines", function()
    local lines, spans = text.wrap_styled("aa bb cc dd", 5, { { from = 3, to = 8, group = "G" } })
    assert.same({ "aa bb", "cc dd" }, lines)
    assert.same({
      { line = 1, col_start = 3, col_end = 5, hl_group = "G" },
      { line = 2, col_start = 0, col_end = 2, hl_group = "G" },
    }, spans)
  end)

  it("covers the collapsed space inside a range and uses byte columns", function()
    local _, spans = text.wrap_styled("é  日 x", 20, { { from = 0, to = 8, group = "G" } })
    assert.same({ { line = 1, col_start = 0, col_end = 6, hl_group = "G" } }, spans)
  end)

  it("keeps ranges across a hard-split word and never exceeds the width", function()
    local lines, spans = text.wrap_styled("abcdefgh", 3, { { from = 2, to = 7, group = "G" } })
    assert.same({ "abc", "def", "gh" }, lines)
    assert.same({
      { line = 1, col_start = 2, col_end = 3, hl_group = "G" },
      { line = 2, col_start = 0, col_end = 3, hl_group = "G" },
      { line = 3, col_start = 0, col_end = 1, hl_group = "G" },
    }, spans)
    for _, l in ipairs(text.wrap_styled("日本語 日本語 x", 4, {})) do
      assert.is_true(text.width(l) <= 4)
    end
  end)

  it("treats newline as a hard break and offsets ranges after it", function()
    local lines, spans = text.wrap_styled("aa bb\ncc", 20, { { from = 6, to = 8, group = "G" } })
    assert.same({ "aa bb", "cc" }, lines)
    assert.same({ { line = 2, col_start = 0, col_end = 2, hl_group = "G" } }, spans)
  end)
end)

describe("core.text hard_wrap and expand_tabs", function()
  it("cuts at the width and keeps spaces", function()
    assert.same({ "ab c", "d  e" }, text.hard_wrap("ab cd  e", 4))
  end)

  it("fits exactly in one row", function()
    assert.same({ "abcd" }, text.hard_wrap("abcd", 4))
  end)

  it("returns one empty row for an empty string", function()
    assert.same({ "" }, text.hard_wrap("", 4))
  end)

  it("handles width 1 and below", function()
    assert.same({ "a", "b", "c" }, text.hard_wrap("abc", 1))
    assert.same({ "a", "b" }, text.hard_wrap("ab", 0))
  end)

  it("never splits a wide char and never exceeds the width", function()
    local rows = text.hard_wrap("日本語a", 5)
    assert.same({ "日本", "語a" }, rows)
    assert_fits(rows, 5)
    assert.same({ "日", "本" }, text.hard_wrap("日本", 1))
  end)

  it("expands tabs to the next stop", function()
    assert.equals("    a", text.expand_tabs("\ta"))
    assert.equals("ab  c", text.expand_tabs("ab\tc"))
    assert.equals("日  x", text.expand_tabs("日\tx"))
  end)
end)
