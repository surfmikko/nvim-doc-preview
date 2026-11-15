local model = require("doc_preview.document.model")
local render = require("doc_preview.document.render")
local block = require("doc_preview.markdown.block")
local text = require("doc_preview.core.text")

local function assert_fits(lines, width)
  for _, l in ipairs(lines) do
    assert.is_true(text.width(l) <= width, l)
  end
end

describe("document.model", function()
  it("validates a tree and rejects unknown kinds or missing ranges", function()
    local doc = model.document({ model.paragraph({ model.text("a") }, 1, 1) }, 1, 1)
    assert.is_true(model.validate(doc))
    assert.is_false(model.validate({ kind = "bogus" }))
    assert.is_false(model.validate(model.document({ { kind = "paragraph", inlines = {} } }, 1, 1)))
  end)
end)

describe("document.model footnotes", function()
  it("validates a footnote_def and an inline footnote_ref without range", function()
    local def = model.footnote_def("a", { model.paragraph({ model.text("x") }, 2, 2) }, 2, 2)
    local p = model.paragraph({ model.text("t"), model.footnote_ref("a") }, 1, 1)
    assert.is_true(model.validate(model.document({ p, def }, 1, 2)))
  end)

  it("rejects an empty label, a missing label and missing children", function()
    local p = model.paragraph({ model.footnote_ref("") }, 1, 1)
    assert.is_false(model.validate(model.document({ p }, 1, 1)))
    assert.is_false(model.validate(model.footnote_ref(nil)))
    local def = { kind = "footnote_def", label = "a", src_start = 1, src_end = 1 }
    assert.is_false(model.validate(def))
    assert.is_false(model.validate(model.footnote_def("", {}, 1, 1)))
  end)
end)

describe("document.model inlines", function()
  it("validates inline kinds without source ranges", function()
    local p = model.paragraph({
      model.emph({ model.strong({ model.text("a") }) }),
      model.strike({ model.text("b") }),
      model.code("c"),
      model.softbreak(),
      model.hardbreak(),
    }, 1, 1)
    assert.is_true(model.validate(model.document({ p }, 1, 1)))
  end)
end)

describe("document.model links", function()
  it("builds links and images and validates them without source ranges", function()
    local link = model.link("/u", "t", { model.emph({ model.text("a") }) })
    local img = model.image("/i", nil, "alt")
    assert.equals("/u", link.target)
    assert.equals("alt", img.alt)
    assert.is_true(model.validate(model.document({ model.paragraph({ link, img }, 1, 1) }, 1, 1)))
  end)
end)

describe("document.model heading", function()
  it("validates levels 1-6 and rejects others", function()
    for level = 1, 6 do
      local h = model.heading(level, { model.text("a") }, 1, 1)
      assert.equals(level, h.level)
      assert.is_true(model.validate(model.document({ h }, 1, 1)))
    end
    assert.has_error(function()
      model.heading(0, {}, 1, 1)
    end)
    assert.has_error(function()
      model.heading(7, {}, 1, 1)
    end)
  end)
end)

describe("document.render heading", function()
  local function doc(h)
    return model.document({ h }, 1, 1)
  end

  it("renders levels 1-6 with a whole-line span and a map entry", function()
    for level = 1, 6 do
      local o =
        render.render(doc(model.heading(level, { model.text("Title") }, 3, 3)), { width = 20 })
      assert.same({ "Title" }, o.lines)
      assert.same(
        { { line = 1, col_start = 0, col_end = 5, hl_group = "DocPreviewH" .. level } },
        o.spans
      )
      assert.same({ { out_start = 1, out_end = 1, src_start = 3, src_end = 3 } }, o.map)
    end
  end)

  it("wraps within ctx.width with one span per line", function()
    local h = model.heading(2, { model.text("aaa bbb ccc ddd eee fff") }, 1, 2)
    local o = render.render(doc(h), { width = 8 })
    assert.same({ "aaa bbb", "ccc ddd", "eee fff" }, o.lines)
    assert.equals(3, #o.spans)
    for i, l in ipairs(o.lines) do
      assert.is_true(text.width(l) <= 8)
      assert.same({ line = i, col_start = 0, col_end = #l, hl_group = "DocPreviewH2" }, o.spans[i])
    end
    assert.same({ { out_start = 1, out_end = 3, src_start = 1, src_end = 2 } }, o.map)
  end)

  it("renders an empty heading as one empty line without a span", function()
    local o = render.render(doc(model.heading(1, { model.text("") }, 1, 1)), {})
    assert.same({ "" }, o.lines)
    assert.same({}, o.spans)
  end)

  it("rebases spans after a preceding block", function()
    local d = model.document({
      model.paragraph({ model.text("p") }, 1, 1),
      model.heading(1, { model.text("h") }, 3, 3),
    }, 1, 3)
    local o = render.render(d, { width = 10 })
    assert.same({ "p", "", "h" }, o.lines)
    assert.equals(3, o.spans[1].line)
  end)
end)

describe("document.render", function()
  after_each(function()
    render.test_hook = nil
  end)

  it("renders paragraphs separated by a blank line, with a source map", function()
    local o = render.render(block.parse({ "a", "b", "", "c" }), { width = 10 })
    assert.same({ "a b", "", "c" }, o.lines)
    assert.same({
      { out_start = 1, out_end = 1, src_start = 1, src_end = 2 },
      { out_start = 3, out_end = 3, src_start = 4, src_end = 4 },
    }, o.map)
  end)

  local function para(str, s1, s2)
    return model.paragraph({ model.text(str) }, s1, s2)
  end

  it("wraps a long paragraph to ctx.width with one map entry", function()
    local doc = model.document({ para("aaa bbb ccc ddd eee fff", 1, 1) }, 1, 1)
    local o = render.render(doc, { width = 8 })
    assert.same({ "aaa bbb", "ccc ddd", "eee fff" }, o.lines)
    assert.same({ { out_start = 1, out_end = 3, src_start = 1, src_end = 1 } }, o.map)
    for _, l in ipairs(o.lines) do
      assert.is_true(text.width(l) <= 8)
    end
    assert.equals(1, o:src_to_out(1))
    assert.equals(1, o:out_to_src(3))
  end)

  it("wraps wide chars without overflowing", function()
    local doc = model.document({ para("日本語テキスト日本語", 1, 2) }, 1, 2)
    local o = render.render(doc, { width = 7 })
    assert.same({ "日本語", "テキス", "ト日本", "語" }, o.lines)
    assert.same({ { out_start = 1, out_end = 4, src_start = 1, src_end = 2 } }, o.map)
  end)

  it("uses a default width without ctx.width", function()
    local long = string.rep("word ", 30)
    local o = render.render(model.document({ para(long, 1, 1) }, 1, 1), {})
    assert.is_true(#o.lines > 1)
  end)

  it("degrades unknown kinds to a placeholder instead of raising", function()
    local doc = model.document({ { kind = "rst:thing", src_start = 1, src_end = 1 } }, 1, 1)
    assert.same({ "[unsupported: rst:thing]" }, render.render(doc, {}).lines)
  end)

  it("calls the test hook per top-level node", function()
    local seen = 0
    render.test_hook = function()
      seen = seen + 1
    end
    render.render(block.parse({ "a", "", "b" }), {})
    assert.equals(2, seen)
  end)
end)

describe("document.render inline styles", function()
  local function render_md(lines, width)
    return render.render(block.parse(lines), { width = width or 40 })
  end

  it("removes markers and spans the styled text", function()
    local r = render_md({ "a *b* **c** `d` ~~e~~" })
    assert.same({ "a b c d e" }, r.lines)
    assert.same({
      { line = 1, col_start = 2, col_end = 3, hl_group = "DocPreviewEmph" },
      { line = 1, col_start = 4, col_end = 5, hl_group = "DocPreviewStrong" },
      { line = 1, col_start = 6, col_end = 7, hl_group = "DocPreviewCode" },
      { line = 1, col_start = 8, col_end = 9, hl_group = "DocPreviewStrike" },
    }, r.spans)
  end)

  it("nests styles as overlapping spans", function()
    local r = render_md({ "**a *b***" })
    assert.same({ "a b" }, r.lines)
    assert.equals(2, #r.spans)
  end)

  it("wraps styled text without exceeding the width", function()
    local r = render_md({ "*aaa bbb ccc ddd eee*" }, 8)
    for i, l in ipairs(r.lines) do
      assert.is_true(text.width(l) <= 8)
      assert.equals("DocPreviewEmph", r.spans[i].hl_group)
      assert.equals(#l, r.spans[i].col_end)
    end
  end)

  it("renders a hard break as a new line and a soft break as a space", function()
    assert.same({ "a", "b" }, render_md({ "a  ", "b" }).lines)
    assert.same({ "a b" }, render_md({ "a", "b" }).lines)
  end)

  it("combines heading and inline spans", function()
    local r = render_md({ "# a *b*" })
    assert.same({ "a b" }, r.lines)
    assert.equals(2, #r.spans)
  end)
end)

describe("document.render thematic_break", function()
  local function rule_doc(width)
    local d = model.document({ model.thematic_break(2, 2) }, 2, 2)
    assert.is_true(model.validate(d))
    return render.render(d, { width = width })
  end

  it("renders one line of ctx.width glyphs with a map entry and no span", function()
    local o = rule_doc(40)
    assert.same({ string.rep("─", 40) }, o.lines)
    assert.same({}, o.spans)
    assert.same({ { out_start = 1, out_end = 1, src_start = 2, src_end = 2 } }, o.map)
  end)

  it("defaults to width 80", function()
    assert.same({ string.rep("─", 80) }, rule_doc(nil).lines)
  end)

  it("renders width 1", function()
    assert.same({ "─" }, rule_doc(1).lines)
  end)

  it("is separated from paragraphs by blank lines", function()
    local d = model.document({
      model.paragraph({ model.text("a") }, 1, 1),
      model.thematic_break(3, 3),
      model.paragraph({ model.text("b") }, 5, 5),
    }, 1, 5)
    local o = render.render(d, { width = 4 })
    assert.same({ "a", "", "────", "", "b" }, o.lines)
    assert.same({ out_start = 3, out_end = 3, src_start = 3, src_end = 3 }, o.map[2])
  end)
end)

describe("document.render blockquote", function()
  local function para(str, s1, s2)
    return model.paragraph({ model.text(str) }, s1, s2)
  end
  local function render_quote(children, width)
    local doc = model.document({ model.blockquote(children, 1, 9) }, 1, 9)
    assert.is_true(model.validate(doc))
    return render.render(doc, { width = width })
  end

  it("prefixes a single paragraph, with prefix span and map entry", function()
    local o = render_quote({ para("a", 1, 1) }, 10)
    assert.same({ "│ a" }, o.lines)
    local quote = { line = 1, col_start = 0, col_end = #"│ ", hl_group = "DocPreviewQuote" }
    assert.same({ quote }, o.spans)
    assert.same({ { out_start = 1, out_end = 1, src_start = 1, src_end = 1 } }, o.map)
  end)

  it("prefixes every wrapped line within the width", function()
    local o = render_quote({ para("aaa bbb ccc ddd", 1, 1) }, 9)
    assert.same({ "│ aaa bbb", "│ ccc ddd" }, o.lines)
    for _, l in ipairs(o.lines) do
      assert.is_true(text.width(l) <= 9)
    end
  end)

  it("separates children with a prefixed blank line and maps each child", function()
    local o = render_quote({ para("a", 2, 2), para("b", 4, 5) }, 10)
    assert.same({ "│ a", "│ ", "│ b" }, o.lines)
    assert.same({
      { out_start = 1, out_end = 1, src_start = 2, src_end = 2 },
      { out_start = 3, out_end = 3, src_start = 4, src_end = 5 },
    }, o.map)
    assert.equals(3, #o.spans)
  end)

  it("shrinks the width per nesting level", function()
    local inner = model.blockquote({ para("aaa bbb", 2, 2) }, 2, 2)
    local o = render_quote({ inner }, 9)
    assert.same({ "│ │ aaa", "│ │ bbb" }, o.lines)
    assert.same({ { out_start = 1, out_end = 2, src_start = 2, src_end = 2 } }, o.map)
  end)

  it("keeps inline spans shifted past the prefix", function()
    local p = model.paragraph({ model.strong({ model.text("b") }) }, 1, 1)
    local o = render_quote({ p }, 10)
    local start = #"│ "
    local bold = { line = 1, col_start = start, col_end = start + 1, hl_group = "DocPreviewStrong" }
    assert.same(bold, o.spans[2])
  end)

  it("maps an empty quote as a whole", function()
    local o = render_quote({}, 10)
    assert.same({ "│ " }, o.lines)
    assert.same({ { out_start = 1, out_end = 1, src_start = 1, src_end = 9 } }, o.map)
  end)

  it("survives a tiny width", function()
    local o = render_quote({ para("abc", 1, 1) }, 1)
    assert.is_true(#o.lines >= 1)
    assert.is_true(text.width(o.lines[1]) <= 1)
  end)
end)

describe("document.render code_block", function()
  local function render_code(lines, width, src_body)
    local node = model.code_block("lua", lines, src_body or 3, 2, 3 + #lines)
    local doc = model.document({ node }, 1, 9)
    assert.is_true(model.validate(doc))
    return render.render(doc, { width = width })
  end
  local code = "DocPreviewCode"

  it("validates lines as strings", function()
    assert.is_false(model.validate(model.code_block(nil, "x", 1, 1, 1)))
    assert.is_false(model.validate(model.code_block(nil, { 1 }, 1, 1, 1)))
  end)

  it("renders lines verbatim with a span and 1:1 map", function()
    local o = render_code({ "a  b", "  c " }, 10)
    assert.same({ "a  b", "  c " }, o.lines)
    assert.same({
      { line = 1, col_start = 0, col_end = 4, hl_group = code },
      { line = 2, col_start = 0, col_end = 4, hl_group = code },
    }, o.spans)
    assert.same({
      { out_start = 1, out_end = 1, src_start = 3, src_end = 3 },
      { out_start = 2, out_end = 2, src_start = 4, src_end = 4 },
    }, o.map)
  end)

  it("renders an empty block as one empty row mapped to the node", function()
    local o = render_code({}, 10)
    assert.same({ "" }, o.lines)
    assert.same({}, o.spans)
    assert.same({ { out_start = 1, out_end = 1, src_start = 2, src_end = 3 } }, o.map)
  end)

  it("keeps blank lines without spans", function()
    local o = render_code({ "a", "", "b" }, 10)
    assert.same({ "a", "", "b" }, o.lines)
    assert.equals(2, #o.spans)
    assert.same({ out_start = 2, out_end = 2, src_start = 4, src_end = 4 }, o.map[2])
  end)

  it("hard-wraps long lines, rows share the source line", function()
    local o = render_code({ "abcdefghij", "x" }, 4)
    assert.same({ "abcd", "efgh", "ij", "x" }, o.lines)
    assert.same({ out_start = 1, out_end = 3, src_start = 3, src_end = 3 }, o.map[1])
    assert.same({ out_start = 4, out_end = 4, src_start = 4, src_end = 4 }, o.map[2])
    assert.equals(4, #o.spans)
    assert_fits(o.lines, 4)
  end)

  it("expands tabs and counts unicode by display width", function()
    local o = render_code({ "\tx", "日本語" }, 4)
    assert.same({ "    ", "x", "日本", "語" }, o.lines)
    assert_fits(o.lines, 4)
  end)

  it("survives a tiny width", function()
    local o = render_code({ "abc" }, 1)
    assert.same({ "a", "b", "c" }, o.lines)
  end)

  it("separates blocks with a blank line", function()
    local doc = model.document({
      model.code_block(nil, { "a" }, 1, 1, 1),
      model.code_block(nil, { "b" }, 3, 3, 3),
    }, 1, 3)
    assert.same({ "a", "", "b" }, render.render(doc, { width = 5 }).lines)
  end)

  it("applies the quote prefix and reduced width", function()
    local node = model.code_block(nil, { "abcdef" }, 2, 1, 3)
    local doc = model.document({ model.blockquote({ node }, 1, 3) }, 1, 3)
    local o = render.render(doc, { width = 6 })
    assert.same({ "│ abcd", "│ ef" }, o.lines)
    assert.same(
      { line = 1, col_start = #"│ ", col_end = #"│ " + 4, hl_group = code },
      o.spans[3]
    )
    assert.same({ out_start = 1, out_end = 2, src_start = 2, src_end = 2 }, o.map[1])
  end)

  it("applies the hanging indent in a list item", function()
    local node = model.code_block(nil, { "abcdef", "g" }, 2, 1, 3)
    local item = model.list_item(nil, { node }, 1, 3)
    local doc = model.document({ model.list(false, 1, true, { item }, 1, 3) }, 1, 3)
    local o = render.render(doc, { width = 6 })
    assert.same({ "• abcd", "  ef", "  g" }, o.lines)
    for _, l in ipairs(o.lines) do
      assert.is_true(text.width(l) <= 6)
    end
    local spans = {}
    for _, s in ipairs(o.spans) do
      if s.hl_group == code then
        spans[#spans + 1] = s.line .. ":" .. s.col_start .. "-" .. s.col_end
      end
    end
    assert.same({ "1:4-8", "2:2-4", "3:2-3" }, spans)
  end)
end)

describe("document.render list", function()
  local function para(str, s1, s2)
    return model.paragraph({ model.text(str) }, s1, s2 or s1)
  end
  local function item(children, checked, s1, s2)
    return model.list_item(checked, children, s1 or 1, s2 or 1)
  end
  local function render_list(list, width)
    local doc = model.document({ list }, 1, 20)
    assert.is_true(model.validate(doc))
    return render.render(doc, { width = width or 20 })
  end
  local function bullets(items, tight)
    return model.list(false, 1, tight ~= false, items, 1, 20)
  end
  local function assert_out_fits(o, width)
    for _, l in ipairs(o.lines) do
      assert.is_true(text.width(l) <= width, l)
    end
  end

  it("renders a bullet list with marker span and map entries", function()
    local o =
      render_list(bullets({ item({ para("a", 1) }, nil, 1, 1), item({ para("b", 2) }, nil, 2, 2) }))
    assert.same({ "• a", "• b" }, o.lines)
    local mark = { line = 1, col_start = 0, col_end = #"• ", hl_group = "DocPreviewListMarker" }
    assert.same(mark, o.spans[1])
    assert.equals(2, o.spans[2].line)
    assert.same({
      { out_start = 1, out_end = 1, src_start = 1, src_end = 1 },
      { out_start = 2, out_end = 2, src_start = 2, src_end = 2 },
    }, o.map)
  end)

  it("numbers ordered lists from start", function()
    local from1 =
      model.list(true, 1, true, { item({ para("a", 1) }), item({ para("b", 2) }) }, 1, 2)
    assert.same({ "1. a", "2. b" }, render_list(from1).lines)
    local from7 =
      model.list(true, 7, true, { item({ para("a", 1) }), item({ para("b", 2) }) }, 1, 2)
    assert.same({ "7. a", "8. b" }, render_list(from7).lines)
  end)

  it("aligns item text when numbers gain a digit", function()
    local o = render_list(
      model.list(true, 9, true, { item({ para("a", 1) }), item({ para("b", 2) }) }, 1, 2)
    )
    assert.same({ " 9. a", "10. b" }, o.lines)
  end)

  it("hangs wrapped lines under the text within the width", function()
    local o = render_list(bullets({ item({ para("aaa bbb ccc ddd", 1) }) }), 9)
    assert.same({ "• aaa bbb", "  ccc ddd" }, o.lines)
    assert_out_fits(o, 9)
  end)

  it("separates items by a blank line only when loose", function()
    local items = { item({ para("a", 1) }), item({ para("b", 3) }) }
    assert.same({ "• a", "", "• b" }, render_list(bullets(items, false)).lines)
    assert.same({ "• a", "• b" }, render_list(bullets(items, true)).lines)
  end)

  it("indents a nested list and keeps a tight paragraph attached", function()
    local inner = model.list(false, 1, true, { item({ para("b", 2) }, nil, 2, 2) }, 2, 2)
    local o = render_list(bullets({ item({ para("a", 1), inner }, nil, 1, 2) }))
    assert.same({ "• a", "  ◦ b" }, o.lines)
    assert.equals(2, #o.map)
  end)

  it("renders task markers, keeping the number for ordered items", function()
    local o = render_list(bullets({ item({ para("a", 1) }, false), item({ para("b", 2) }, true) }))
    assert.same({ "[ ] a", "[x] b" }, o.lines)
    local ord = model.list(true, 1, true, { item({ para("a", 1) }, true) }, 1, 1)
    assert.same({ "1. [x] a" }, render_list(ord).lines)
  end)

  it("renders an empty item as the marker alone mapped to its line", function()
    local o = render_list(bullets({ item({}, nil, 3, 3) }))
    assert.same({ "• " }, o.lines)
    assert.same({ { out_start = 1, out_end = 1, src_start = 3, src_end = 3 } }, o.map)
  end)

  it("keeps blank lines between item paragraphs empty", function()
    local o = render_list(bullets({ item({ para("a", 1), para("b", 3) }, nil, 1, 3) }))
    assert.same({ "• a", "", "  b" }, o.lines)
    assert.same({
      { out_start = 1, out_end = 1, src_start = 1, src_end = 1 },
      { out_start = 3, out_end = 3, src_start = 3, src_end = 3 },
    }, o.map)
  end)

  it("works inside a block quote", function()
    local list = bullets({ item({ para("aaa bbb", 1) }) })
    local doc = model.document({ model.blockquote({ list }, 1, 1) }, 1, 1)
    local o = render.render(doc, { width = 9 })
    assert.same({ "│ • aaa", "│   bbb" }, o.lines)
    assert_out_fits(o, 9)
  end)

  it("survives a tiny width", function()
    local o = render_list(bullets({ item({ para("abc", 1) }) }), 1)
    assert.is_true(#o.lines >= 1)
    assert.is_true(o.lines[1]:sub(1, #"• ") == "• ")
  end)

  it("shifts inline spans past the marker", function()
    local p = model.paragraph({ model.strong({ model.text("b") }) }, 1, 1)
    local o = render_list(bullets({ item({ p }) }))
    local start = #"• "
    assert.same(
      { line = 1, col_start = start, col_end = start + 1, hl_group = "DocPreviewStrong" },
      o.spans[2]
    )
  end)
end)

describe("document.render html_block", function()
  local html = "DocPreviewHtml"
  local function render_html(lines, width, src_body)
    local node = model.html_block(lines, src_body or 3, 2, 3 + #lines)
    local doc = model.document({ node }, 1, 9)
    assert.is_true(model.validate(doc))
    return render.render(doc, { width = width })
  end

  it("validates lines as strings", function()
    assert.is_false(model.validate(model.html_block("x", 1, 1, 1)))
    assert.is_false(model.validate(model.html_block({ 1 }, 1, 1, 1)))
  end)

  it("renders lines verbatim with a span and 1:1 map", function()
    local o = render_html({ "<div>", "  <p>x</p> " }, 20)
    assert.same({ "<div>", "  <p>x</p> " }, o.lines)
    assert.same({
      { line = 1, col_start = 0, col_end = 5, hl_group = html },
      { line = 2, col_start = 0, col_end = 11, hl_group = html },
    }, o.spans)
    assert.same({
      { out_start = 1, out_end = 1, src_start = 3, src_end = 3 },
      { out_start = 2, out_end = 2, src_start = 4, src_end = 4 },
    }, o.map)
  end)

  it("renders an empty block as one empty row mapped to the node", function()
    local o = render_html({}, 10)
    assert.same({ "" }, o.lines)
    assert.same({}, o.spans)
    assert.same({ { out_start = 1, out_end = 1, src_start = 2, src_end = 3 } }, o.map)
  end)

  it("keeps blank lines without spans and the indent", function()
    local o = render_html({ "   <!--", "", "-->" }, 10)
    assert.same({ "   <!--", "", "-->" }, o.lines)
    assert.equals(2, #o.spans)
    assert.same({ out_start = 2, out_end = 2, src_start = 4, src_end = 4 }, o.map[2])
  end)

  it("hard-wraps long lines, rows share the source line", function()
    local o = render_html({ "<abcdefghi>", "x" }, 4)
    assert.same({ "<abc", "defg", "hi>", "x" }, o.lines)
    assert.same({ out_start = 1, out_end = 3, src_start = 3, src_end = 3 }, o.map[1])
    assert.same({ out_start = 4, out_end = 4, src_start = 4, src_end = 4 }, o.map[2])
    assert.equals(4, #o.spans)
    assert_fits(o.lines, 4)
  end)

  it("expands tabs and counts unicode by display width", function()
    local o = render_html({ "\tx", "日本語" }, 4)
    assert.same({ "    ", "x", "日本", "語" }, o.lines)
    assert_fits(o.lines, 4)
  end)

  it("survives a tiny width", function()
    assert.same({ "<", "b", ">" }, render_html({ "<b>" }, 1).lines)
  end)

  it("applies the quote prefix and reduced width", function()
    local node = model.html_block({ "<abcdef>" }, 2, 1, 3)
    local doc = model.document({ model.blockquote({ node }, 1, 3) }, 1, 3)
    local o = render.render(doc, { width = 6 })
    assert.same({ "│ <abc", "│ def>" }, o.lines)
    assert.same(
      { line = 1, col_start = #"│ ", col_end = #"│ " + 4, hl_group = html },
      o.spans[3]
    )
  end)

  it("applies the hanging indent in a list item", function()
    local node = model.html_block({ "<abcdef>", "g" }, 2, 1, 3)
    local item = model.list_item(nil, { node }, 1, 3)
    local doc = model.document({ model.list(false, 1, true, { item }, 1, 3) }, 1, 3)
    local o = render.render(doc, { width = 6 })
    assert.same({ "• <abc", "  def>", "  g" }, o.lines)
    assert_fits(o.lines, 6)
  end)
end)

describe("document.render html_inline", function()
  local html = "DocPreviewHtml"
  local function render_para(inlines, width)
    local doc = model.document({ model.paragraph(inlines, 1, 1) }, 1, 1)
    assert.is_true(model.validate(doc))
    return render.render(doc, { width = width })
  end

  it("validates value as a string", function()
    assert.is_false(model.validate(model.html_inline(1)))
  end)

  it("renders the value in the flow with a span", function()
    local o = render_para({ model.text("a "), model.html_inline("<b>"), model.text(" c") }, 20)
    assert.same({ "a <b> c" }, o.lines)
    assert.same({ { line = 1, col_start = 2, col_end = 5, hl_group = html } }, o.spans)
  end)

  it("turns a newline in the value into a space", function()
    local o = render_para({ model.html_inline('<a\nhref="x">') }, 40)
    assert.same({ '<a href="x">' }, o.lines)
  end)

  it("wraps with the surrounding text", function()
    local o = render_para({ model.text("aaa "), model.html_inline("<b>"), model.text(" ccc") }, 8)
    assert.same({ "aaa <b>", "ccc" }, o.lines)
    assert_fits(o.lines, 8)
    assert.same({ line = 1, col_start = 4, col_end = 7, hl_group = html }, o.spans[1])
  end)

  it("sits next to emphasis", function()
    local o = render_para({ model.emph({ model.text("e") }), model.html_inline("<i>") }, 20)
    assert.same({ "e<i>" }, o.lines)
    assert.same({ "DocPreviewEmph", html }, { o.spans[1].hl_group, o.spans[2].hl_group })
  end)
end)

describe("document.render table", function()
  local function cell(s)
    return { inlines = { model.text(s) } }
  end
  local function tbl(align, header, rows)
    return model.table(align, header, rows, 3, 4 + #rows)
  end
  local function render_tbl(node, ctx, children)
    local doc = model.document(children or { node }, 1, 20)
    assert.is_true(model.validate(doc))
    return render.render(doc, ctx or { width = 40 })
  end
  local simple = function()
    return tbl({}, { cell("a"), cell("b") }, { { cell("c"), cell("d") } })
  end

  it("validates align, ragged rows and cells", function()
    assert.is_true(model.validate(simple()))
    assert.is_false(model.validate(tbl({ "up" }, { cell("a") }, {})))
    assert.is_false(model.validate(tbl({}, { cell("a"), cell("b") }, { { cell("c") } })))
    assert.is_false(model.validate(tbl({}, { {} }, {})))
    assert.is_false(model.validate(tbl({}, { { inlines = { { kind = "bogus" } } } }, {})))
  end)

  it("renders a 2x2 table exactly", function()
    local o = render_tbl(simple())
    assert.same({
      "┌───┬───┐",
      "│ a │ b │",
      "├───┼───┤",
      "│ c │ d │",
      "└───┴───┘",
    }, o.lines)
  end)

  it("aligns cells and keeps empty cells", function()
    local node = tbl(
      { "right", "center", "left" },
      { cell("hhhh"), cell("hhhh"), cell("hhhh") },
      { { cell("a"), cell("b"), cell("") } }
    )
    local o = render_tbl(node)
    assert.equals("│    a │  b   │      │", o.lines[4])
  end)

  it("renders a header-only table with the header separator", function()
    local o = render_tbl(tbl({}, { cell("a") }, {}))
    assert.same({ "┌───┐", "│ a │", "├───┤", "└───┘" }, o.lines)
    assert.same(
      { 3, 3, 4, 4 },
      vim.tbl_map(function(m)
        return m.src_start
      end, o.map)
    )
  end)

  it("uses ascii glyphs for ctx.charset = ascii", function()
    local o = render_tbl(simple(), { width = 40, charset = "ascii" })
    assert.equals("+---+---+", o.lines[1])
    assert.equals("| a | b |", o.lines[2])
  end)

  it("wraps cells so no row exceeds the width", function()
    local node = tbl({}, { cell("head one"), cell("head two") }, {
      { cell("alpha beta gamma delta"), cell("epsilon zeta eta theta") },
    })
    for width = 9, 30 do
      assert_fits(render_tbl(node, { width = width }).lines, width)
    end
    local o = render_tbl(node, { width = 20 })
    assert.is_true(#o.lines > 5)
  end)

  it("counts wide characters by display width", function()
    local o = render_tbl(tbl({}, { cell("漢字") }, { { cell("a") } }))
    assert.same({
      "┌──────┐",
      "│ 漢字 │",
      "├──────┤",
      "│ a    │",
      "└──────┘",
    }, o.lines)
    assert_fits(render_tbl(tbl({}, { cell("漢字漢字") }, {}), { width = 7 }).lines, 7)
  end)

  it("degrades to plain rows at a tiny width", function()
    local node = tbl({}, { cell("ab"), cell("cd") }, { { cell("ef"), cell("gh") } })
    local o = render_tbl(node, { width = 4 })
    assert_fits(o.lines, 4)
    assert.is_true(#o.lines >= 2)
  end)

  it("styles inline markup and numbers links in cells", function()
    local link = model.link("http://x", nil, { model.text("l") })
    local node = tbl({}, { { inlines = { model.strong({ model.text("h") }) } } }, {
      { { inlines = { link } } },
    })
    local o = render_tbl(node)
    assert.equals("│ l[1] │", o.lines[4])
    local groups = {}
    for _, s in ipairs(o.spans) do
      if s.line == 4 then
        groups[#groups + 1] = s.hl_group
      end
    end
    assert.is_true(vim.tbl_contains(groups, "DocPreviewLink"))
    assert.is_true(vim.tbl_contains(groups, "DocPreviewLinkMark"))
    local link_span
    for _, s in ipairs(o.spans) do
      if s.line == 4 and s.hl_group == "DocPreviewLink" then
        link_span = s
      end
    end
    assert.equals(#"│ ", link_span.col_start)
    assert.equals(#"│ l", link_span.col_end)
    assert.is_true(vim.iter(o.lines):any(function(l)
      return l:find("http://x", 1, true)
    end))
  end)

  it("styles header and borders", function()
    local o = render_tbl(simple())
    local function has(line, group)
      for _, s in ipairs(o.spans) do
        if s.line == line and s.hl_group == group then
          return true
        end
      end
      return false
    end
    assert.is_true(has(1, "DocPreviewTableBorder"))
    assert.is_true(has(3, "DocPreviewTableBorder"))
    assert.is_true(has(5, "DocPreviewTableBorder"))
    assert.is_true(has(2, "DocPreviewTableHeader"))
    assert.is_true(has(2, "DocPreviewStrong"))
    assert.is_true(has(2, "DocPreviewTableBorder"))
    assert.is_true(has(4, "DocPreviewTableBorder"))
    assert.is_false(has(4, "DocPreviewTableHeader"))
  end)

  it("maps every row to its source line, ascending", function()
    local node = tbl({}, { cell("h1"), cell("h2") }, {
      { cell("alpha beta gamma delta epsilon"), cell("x") },
      { cell("y"), cell("z") },
    })
    local o = render_tbl(node, { width = 16 })
    local covered, last = {}, 0
    for _, m in ipairs(o.map) do
      assert.is_true(m.src_start >= last)
      last = m.src_start
      for l = m.out_start, m.out_end do
        covered[l] = m.src_start
      end
    end
    for l = 1, #o.lines do
      assert.is_not_nil(covered[l], "row " .. l)
    end
    assert.equals(3, covered[1])
    assert.equals(3, covered[2])
    assert.equals(4, covered[3])
    assert.equals(5, covered[4])
    assert.equals(5, covered[5])
    assert.equals(6, covered[#o.lines - 1])
    assert.equals(6, covered[#o.lines])
  end)

  it("renders inside a block quote and a list item", function()
    local quote = render_tbl(nil, { width = 20 }, { model.blockquote({ simple() }, 1, 6) })
    assert.equals("│ ┌───┬───┐", quote.lines[1])
    assert_fits(quote.lines, 20)
    local item = model.list_item(nil, { simple() }, 3, 6)
    local list = model.list(false, 1, true, { item }, 3, 6)
    local o = render_tbl(nil, { width = 20 }, { list })
    assert.equals("• ┌───┬───┐", o.lines[1])
    assert.equals("  │ a │ b │", o.lines[2])
    assert_fits(o.lines, 20)
  end)
end)

describe("document.render image", function()
  local img = "DocPreviewImage"
  local function render_doc(children, width)
    local doc = model.document(children, 1, 20)
    assert.is_true(model.validate(doc))
    return render.render(doc, { width = width })
  end
  local function para(inlines)
    return model.paragraph(inlines, 1, 1)
  end

  it("validates block and inline images", function()
    assert.is_false(model.validate({ kind = "image", target = "/i" }))
    assert.is_false(model.validate({ kind = "image", alt = "a" }))
    assert.is_false(model.validate({ kind = "image", block = true, target = "/i", alt = "a" }))
    assert.is_true(model.validate(model.image_block("/i", nil, "a", 1, 1)))
    assert.is_true(model.validate(model.image("/i", nil, "a")))
  end)

  it("renders an inline image as a dim placeholder", function()
    local o = render_doc(
      { para({ model.text("a "), model.image("/i", "T", "cat"), model.text(" b") }) },
      40
    )
    assert.same({ "a [image: cat] b" }, o.lines)
    assert.same({ { line = 1, col_start = 2, col_end = 14, hl_group = img } }, o.spans)
  end)

  it("renders empty alt as [image] and newlines in alt as spaces", function()
    assert.same({ "[image]" }, render_doc({ para({ model.image("/i", nil, "") }) }, 40).lines)
    local o = render_doc({ para({ model.image("/i", nil, "a\nb") }) }, 40)
    assert.same({ "[image: a b]" }, o.lines)
  end)

  it("wraps a long inline placeholder with spans on each row", function()
    local o = render_doc({ para({ model.image("/i", nil, "one two three four five") }) }, 12)
    assert.is_true(#o.lines > 1)
    assert_fits(o.lines, 12)
    local seen = {}
    for _, s in ipairs(o.spans) do
      assert.equals(img, s.hl_group)
      seen[s.line] = true
    end
    for i = 1, #o.lines do
      assert.is_true(seen[i])
    end
  end)

  it("keeps the link underline and marker around an image", function()
    local link = model.link("/u", nil, { model.image("/i", nil, "x") })
    local o = render_doc({ para({ link }) }, 40)
    assert.same({ "[image: x][1]", "", "Links", "[1] /u" }, o.lines)
    local groups = {}
    for _, s in ipairs(o.spans) do
      if s.line == 1 then
        groups[s.hl_group] = { s.col_start, s.col_end }
      end
    end
    assert.same({ 0, 10 }, groups.DocPreviewLink)
    assert.same({ 0, 10 }, groups[img])
    assert.same({ 10, 13 }, groups.DocPreviewLinkMark)
  end)

  it("renders in a heading and a table cell", function()
    local h = model.heading(1, { model.image("/i", nil, "h") }, 1, 1)
    assert.same({ "[image: h]" }, render_doc({ h }, 40).lines)
    local t = model.table(
      {},
      { { inlines = { model.image("/i", nil, "c") } } },
      { { { inlines = { model.text("d") } } } },
      1,
      3
    )
    local o = render_doc({ t }, 40)
    assert.is_truthy(o.lines[2]:find("[image: c]", 1, true))
  end)

  it("renders a block image exactly with one map entry over all rows", function()
    local o = render_doc({ model.image_block("/i", nil, "cat", 3, 5) }, 40)
    assert.same({ "[image: cat]" }, o.lines)
    assert.same({ { line = 1, col_start = 0, col_end = 12, hl_group = img } }, o.spans)
    assert.same({ { out_start = 1, out_end = 1, src_start = 3, src_end = 5 } }, o.map)
  end)

  it("wraps a block image at every width incl. wide characters", function()
    local alt = "alpha beta gamma delta 漢字漢字漢字 epsilon"
    for width = 4, 30 do
      local o = render_doc({ model.image_block("/i", nil, alt, 2, 4) }, width)
      assert_fits(o.lines, width)
      local seen = {}
      for _, s in ipairs(o.spans) do
        assert.equals(img, s.hl_group)
        seen[s.line] = true
      end
      for i = 1, #o.lines do
        assert.is_true(seen[i], "width " .. width .. " row " .. i)
      end
      assert.same({ { out_start = 1, out_end = #o.lines, src_start = 2, src_end = 4 } }, o.map)
    end
  end)

  it("renders a block image in a quote and a list item", function()
    local q = model.blockquote({ model.image_block("/i", nil, "q", 1, 1) }, 1, 1)
    local l = model.list(false, 1, true, {
      model.list_item(nil, { model.image_block("/i", nil, "l", 3, 3) }, 3, 3),
    }, 3, 3)
    local o = render_doc({ q, l }, 40)
    assert.equals("│ [image: q]", o.lines[1])
    assert.equals("• [image: l]", o.lines[3])
    assert.same(
      { line = 1, col_start = #"│ ", col_end = #"│ " + 10, hl_group = img },
      o.spans[2]
    )
  end)
end)

describe("document.render footnotes", function()
  local function P(inlines, a)
    return model.paragraph(inlines, a, a)
  end
  local function ref(label)
    return model.footnote_ref(label)
  end
  local function def(label, children, a, b)
    return model.footnote_def(label, children, a, b or a)
  end
  local function run(children, width)
    local doc = model.document(children, 1, 20)
    return render.render(doc, { width = width or 40 })
  end
  local function groups(o, group)
    local res = {}
    for _, s in ipairs(o.spans) do
      if s.hl_group == group then
        res[#res + 1] = { s.line, s.col_start, s.col_end }
      end
    end
    return res
  end

  it("renders a marker and the section; the definition is not shown in place", function()
    local o =
      run({ P({ model.text("a"), ref("x") }, 1), def("x", { P({ model.text("note") }, 3) }, 3) })
    assert.same({ "a[^1]", "", "Footnotes", "1. note" }, o.lines)
    assert.same({ { 1, 1, 5 } }, groups(o, "DocPreviewFootnoteRef"))
    assert.same({ { 3, 0, 9 } }, groups(o, "DocPreviewH2"))
  end)

  it("numbers by first use and shares the number of a repeated ref", function()
    local o = run({
      P({ ref("b"), model.text(" "), ref("a"), model.text(" "), ref("b") }, 1),
      def("a", { P({ model.text("A") }, 3) }, 3),
      def("b", { P({ model.text("B") }, 4) }, 4),
    })
    assert.same({ "[^1] [^2] [^1]", "", "Footnotes", "1. B", "2. A" }, o.lines)
  end)

  it("omits an unused definition and keeps an undefined ref literal", function()
    local o = run({ P({ ref("zz") }, 1), def("u", { P({ model.text("U") }, 2) }, 2) })
    assert.same({ "[^zz]" }, o.lines)
    assert.same({}, groups(o, "DocPreviewFootnoteRef"))
  end)

  it("renders multi-paragraph, list and code bodies hanging under the number", function()
    local items = {
      model.list_item(nil, { P({ model.text("i") }, 6) }, 6, 6),
    }
    local body = {
      P({ model.text("one") }, 3),
      P({ model.text("two") }, 5),
      model.list(false, nil, true, items, 6, 6),
      model.code_block(nil, { "c" }, 9, 8, 10),
    }
    local o = run({ P({ ref("x") }, 1), def("x", body, 3, 9) })
    assert.same(
      { "[^1]", "", "Footnotes", "1. one", "", "   two", "", "   ◦ i", "", "   c" },
      o.lines
    )
    for i = 5, #o.lines do
      assert.is_true(o:out_to_src(i) ~= nil)
    end
  end)

  it("handles refs in a heading and a table cell", function()
    local h = model.heading(2, { model.text("T"), ref("x") }, 1, 1)
    local t = model.table(
      { "left" },
      { { inlines = { model.text("h") } } },
      { { { inlines = { ref("x") } } } },
      3,
      5
    )
    local o = run({ h, t, def("x", { P({ model.text("n") }, 7) }, 7) })
    assert.same("T[^1]", o.lines[1])
    assert.is_truthy(table.concat(o.lines, "\n"):find("[^1]", 1, true))
    assert.same("1. n", o.lines[#o.lines])
  end)

  it("numbers footnotes separately from links", function()
    local link = model.link("/u", nil, { model.text("l") })
    local o = run({
      P({ link, ref("x"), link }, 1),
      def("x", { P({ model.text("n") }, 3) }, 3),
    })
    assert.same({ "l[1][^1]l[1]", "", "Footnotes", "1. n", "", "Links", "[1] /u" }, o.lines)
  end)

  it("numbers a ref inside a footnote body after earlier ones", function()
    local o = run({
      P({ ref("a") }, 1),
      def("a", { P({ model.text("see"), ref("b") }, 3) }, 3),
      def("b", { P({ model.text("B") }, 4) }, 4),
    })
    assert.same({ "[^1]", "", "Footnotes", "1. see[^2]", "2. B" }, o.lines)
  end)

  it("fits every row in the width, wide characters included", function()
    local long = string.rep("word ", 12) .. "漢字漢字漢字漢字漢字漢字"
    for width = 10, 30 do
      local o = run({
        P({ model.text("t"), ref("x") }, 1),
        def("x", { P({ model.text(long) }, 3), P({ model.text(long) }, 5) }, 3, 5),
      }, width)
      assert_fits(o.lines, width)
    end
  end)

  it("maps the title and entries to the definition, every row covered", function()
    local o = run({
      P({ ref("x") }, 1),
      def("x", { P({ model.text("p") }, 4), P({ model.text("q") }, 6) }, 4, 6),
    })
    assert.same({ "[^1]", "", "Footnotes", "1. p", "", "   q" }, o.lines)
    assert.same(4, o:out_to_src(3))
    assert.same(4, o:out_to_src(4))
    assert.is_true(o:out_to_src(5) ~= nil)
    assert.same(6, o:out_to_src(6))
    local prev = 0
    for _, m in ipairs(o.map) do
      assert.is_true(m.out_start >= prev)
      prev = m.out_start
    end
  end)
end)

describe("document.render charset", function()
  local src = {
    "- a",
    "  - b",
    "    - c",
    "",
    "---",
    "",
    "> q",
    "",
    "| h |",
    "|---|",
    "| x |",
  }

  it("renders unicode by default", function()
    local lines = render.render(block.parse(src), { width = 10 }).lines
    assert.same({ "• a", "  ◦ b", "    ▪ c" }, { lines[1], lines[2], lines[3] })
    assert.is_truthy(table.concat(lines, "\n"):find("──────────", 1, true))
    assert.is_truthy(table.concat(lines, "\n"):find("│ q", 1, true))
  end)

  it("renders ascii rule, quote, bullets and table", function()
    local o = render.render(block.parse(src), { width = 10, charset = "ascii" })
    local all = table.concat(o.lines, "\n")
    assert.same({ "* a", "  - b", "    + c" }, { o.lines[1], o.lines[2], o.lines[3] })
    assert.is_truthy(all:find("----------", 1, true))
    assert.is_truthy(all:find("| q", 1, true))
    assert.is_truthy(all:find("+---+", 1, true))
    assert.is_nil(all:find("[\128-\255]"))
    assert_fits(o.lines, 10)
  end)
end)
