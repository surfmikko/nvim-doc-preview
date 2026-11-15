local tbl = require("doc_preview.core.table")
local text = require("doc_preview.core.text")

local function sum(t)
  local s = 0
  for _, v in ipairs(t) do
    s = s + v
  end
  return s
end

local function cells(...)
  local row = {}
  for i, s in ipairs({ ... }) do
    row[i] = { text = s }
  end
  return row
end

local function assert_fits(items, width)
  for _, it in ipairs(items) do
    assert.is_true(text.width(it.text) <= width, width .. ": " .. it.text)
  end
end

describe("core.table fit", function()
  it("keeps natural widths when they fit", function()
    assert.same({ 5, 10 }, tbl.fit({ 5, 10 }, 20, { 1, 1 }))
  end)

  it("fits exactly at the limit", function()
    assert.same({ 5, 10 }, tbl.fit({ 5, 10 }, 15, { 1, 1 }))
  end)

  it("shrinks proportionally and never exceeds available", function()
    local w = tbl.fit({ 10, 20 }, 15, { 1, 1 })
    assert.equals(15, sum(w))
    assert.is_true(w[1] < w[2])
  end)

  it("respects floors", function()
    local w = tbl.fit({ 30, 4 }, 10, { 5, 4 })
    assert.same({ 6, 4 }, w)
  end)

  it("drops floors to 1 when they do not fit", function()
    local w = tbl.fit({ 30, 30 }, 6, { 8, 8 })
    assert.equals(6, sum(w))
    assert.same({ 3, 3 }, w)
  end)

  it("handles one column", function()
    assert.same({ 7 }, tbl.fit({ 30 }, 7, { 3 }))
  end)

  it("handles many columns", function()
    local nat, mins = {}, {}
    for i = 1, 12 do
      nat[i], mins[i] = 10 + i, 3
    end
    local w = tbl.fit(nat, 40, mins)
    assert.equals(40, sum(w))
    for i, v in ipairs(w) do
      assert.is_true(v >= 3 and v <= nat[i])
    end
  end)

  it("returns nil when width 1 per column does not fit", function()
    assert.is_nil(tbl.fit({ 5, 5, 5 }, 2, { 1, 1, 1 }))
  end)

  it("fits at width 1 per column", function()
    assert.same({ 1, 1, 1 }, tbl.fit({ 5, 5, 5 }, 3, { 1, 1, 1 }))
  end)

  it("sum is exact for a sweep", function()
    for avail = 3, 29 do
      local w = tbl.fit({ 9, 13, 7 }, avail, { 2, 5, 3 })
      assert.equals(avail, sum(w))
    end
  end)
end)

describe("core.table minimum and wrap_cell", function()
  it("uses the longest word capped, widest char as floor", function()
    assert.equals(3, tbl.minimum({ "a bbb cc" }))
    assert.equals(8, tbl.minimum({ "abcdefghijklmnop" }))
    assert.equals(2, tbl.minimum({ "日 a" }))
    assert.equals(1, tbl.minimum({ "" }))
  end)

  it("counts wide characters and combining marks by display width", function()
    assert.equals(4, tbl.minimum({ "日本" }))
    assert.equals(2, tbl.minimum({ "ab\u{301}" }))
  end)

  it("wraps and returns at least one line", function()
    assert.same({ "aa", "bb" }, (tbl.wrap_cell("aa bb", 2)))
    assert.same({ "" }, (tbl.wrap_cell("", 4)))
  end)

  it("hard-wraps a word longer than the column", function()
    assert.same({ "abc", "def", "g" }, (tbl.wrap_cell("abcdefg", 3)))
  end)

  it("returns spans on wrapped lines", function()
    local _, spans = tbl.wrap_cell("aa bb", 2, { { from = 3, to = 5, group = "B" } })
    assert.same({ { line = 2, col_start = 0, col_end = 2, hl_group = "B" } }, spans)
  end)
end)

describe("core.table layout_row", function()
  it("pads by alignment", function()
    local lines = tbl.layout_row(cells("a", "b", "c"), { 3, 3, 3 }, { "left", "right", "center" })
    assert.same({ "│ a   │   b │  c  │" }, lines)
  end)

  it("uses the row height of the tallest cell and pads empty cells", function()
    local lines = tbl.layout_row(cells("aa bb", ""), { 2, 2 }, {})
    assert.same({ "│ aa │    │", "│ bb │    │" }, lines)
  end)

  it("shifts spans to byte columns of the line", function()
    local cs = { { text = "x" }, { text = "yy", ranges = { { from = 0, to = 2, group = "G" } } } }
    local lines, spans = tbl.layout_row(cs, { 1, 4 }, { nil, "right" })
    assert.equals("│ x │   yy │", lines[1])
    local sp = spans[1]
    assert.equals("yy", lines[1]:sub(sp.col_start + 1, sp.col_end))
  end)

  it("uses ascii glyphs", function()
    local lines = tbl.layout_row(cells("a"), { 1 }, {}, "ascii")
    assert.same({ "| a |" }, lines)
  end)
end)

describe("core.table layout", function()
  local grid = {
    cells("Name", "Value"),
    cells("alpha", "1"),
    cells("", "日本語"),
  }

  it("draws a full grid at natural width", function()
    local items = tbl.layout(grid, { "left", "right" }, 80)
    local lines = {}
    for i, it in ipairs(items) do
      lines[i] = it.text
    end
    assert.same({
      "┌───────┬────────┐",
      "│ Name  │  Value │",
      "├───────┼────────┤",
      "│ alpha │      1 │",
      "│       │ 日本語 │",
      "└───────┴────────┘",
    }, lines)
    assert.equals("top", items[1].rule)
    assert.equals(1, items[2].row)
    assert.equals("header", items[3].rule)
    assert.equals(3, items[5].row)
    assert.equals("bottom", items[6].rule)
  end)

  it("draws a header-only table with a separator", function()
    local items = tbl.layout({ cells("a") }, {}, 20)
    assert.equals(4, #items)
    assert.equals("header", items[3].rule)
  end)

  it("wraps cells at narrow width", function()
    local items = tbl.layout({ cells("one two three", "four five six") }, {}, 20)
    assert.is_true(#items > 4)
    assert_fits(items, 20)
  end)

  it("every line fits for widths 1..40, both charsets", function()
    local wide = {
      cells("Header one", "日本語のテキスト", "c"),
      cells("averyveryverylongwordindeed", "x y z", ""),
      cells("é́ combining", "日", "tail words here"),
    }
    local plain = { cells("Header", "b c"), cells("averyverylongword", "") }
    for _, charset in ipairs({ "unicode", "ascii" }) do
      for width = 1, 40 do
        assert_fits(tbl.layout(plain, { "left", "right" }, width, charset), width)
        if width >= 2 then -- a wide character cannot fit one column
          assert_fits(tbl.layout(grid, { "left", "right" }, width, charset), width)
          assert_fits(tbl.layout(wide, { "left", "center", "right" }, width, charset), width)
        end
      end
    end
  end)

  it("falls back to hard-wrapped pipe rows when too narrow", function()
    local items = tbl.layout({ cells("abc", "def"), cells("g", "h") }, {}, 6, "ascii")
    local lines = {}
    for i, it in ipairs(items) do
      lines[i] = it.text
      assert.is_nil(it.rule)
    end
    assert.same({ "|abc|d", "ef|", "|g|h|" }, lines)
  end)

  it("maps spans per item", function()
    local g = { { { text = "hi", ranges = { { from = 0, to = 2, group = "H" } } } } }
    local items = tbl.layout(g, {}, 20)
    local sp = items[2].spans[1]
    assert.equals("hi", items[2].text:sub(sp.col_start + 1, sp.col_end))
  end)
end)
