local model = require("doc_preview.document.model")
local block = require("doc_preview.markdown.block")

-- Plain text of inline nodes: breaks become "\n", styled nodes their content.
local function plain(inlines)
  local parts = {}
  for _, n in ipairs(inlines) do
    if n.kind == "softbreak" or n.kind == "hardbreak" then
      parts[#parts + 1] = "\n"
    else
      parts[#parts + 1] = n.value or plain(n.inlines)
    end
  end
  return table.concat(parts)
end

describe("markdown.block", function()
  it("splits blank-line separated chunks into paragraphs with source ranges", function()
    local doc = block.parse({ "a", "b", "", "", "c", "  ", "d" })
    assert.is_true(model.validate(doc))
    assert.equals(3, #doc.children)
    assert.equals(1, doc.children[1].src_start)
    assert.equals(2, doc.children[1].src_end)
    assert.equals("a\nb", plain(doc.children[1].inlines))
    assert.equals(5, doc.children[2].src_start)
    assert.equals(5, doc.children[2].src_end)
    assert.equals(7, doc.children[3].src_start)
    assert.equals(7, doc.children[3].src_end)
  end)

  it("keeps lazy continuation lines in the paragraph", function()
    local doc = block.parse({ "first", "   second", "third" })
    assert.equals(1, #doc.children)
    assert.equals("first\nsecond\nthird", plain(doc.children[1].inlines))
  end)

  it("strips leading and trailing whitespace of lines", function()
    local doc = block.parse({ "   a  ", "      b\t" })
    assert.equals("a\nb", plain(doc.children[1].inlines))
  end)

  it("gives an empty document for empty input", function()
    local doc = block.parse({ "" })
    assert.equals(0, #doc.children)
    assert.equals(1, doc.src_end)
    assert.is_true(model.validate(doc))
    assert.equals(1, block.parse({}).src_end)
  end)

  it("spans the whole buffer in the document range", function()
    assert.equals(3, block.parse({ "a", "", "b" }).src_end)
  end)

  local function h(line)
    local doc = block.parse(type(line) == "table" and line or { line })
    local n = doc.children[1]
    return n.kind == "heading" and n.level or nil, plain(n.inlines or {}), n
  end

  describe("ATX headings", function()
    it("parses levels 1-6", function()
      for level = 1, 6 do
        local l, content = h(string.rep("#", level) .. " title")
        assert.equals(level, l)
        assert.equals("title", content)
      end
    end)

    it("rejects 7 hashes and a missing space", function()
      assert.is_nil((h("####### x")))
      assert.is_nil((h("#x")))
    end)

    it("allows 0-3 spaces of indent, not 4", function()
      assert.equals(1, (h("   # x")))
      assert.is_nil((h("    # x")))
    end)

    it("expands tabs for the indent", function()
      assert.is_nil((h("\t# x")))
      assert.is_nil((h("  \t# x")))
      assert.equals(2, (h("##\tx")))
    end)

    it("trims content and strips a closing sequence", function()
      assert.equals("foo", select(2, h("#   foo   ")))
      assert.equals("foo", select(2, h("## foo ##   ")))
      assert.equals("foo", select(2, h("# foo \t#\t")))
      assert.equals("foo#", select(2, h("# foo#")))
      assert.equals("foo #", select(2, h("# foo \\#")))
    end)

    it("allows empty headings", function()
      assert.equals(1, (h("#")))
      assert.equals("", select(2, h("#")))
      local l, content = h("## ##")
      assert.equals(2, l)
      assert.equals("", content)
    end)

    it("records source ranges and interrupts paragraphs", function()
      local doc = block.parse({ "a", "# b", "c", "", "## d" })
      assert.is_true(model.validate(doc))
      local kinds = {}
      for _, n in ipairs(doc.children) do
        kinds[#kinds + 1] = n.kind .. ":" .. n.src_start .. "-" .. n.src_end
      end
      assert.same({ "paragraph:1-1", "heading:2-2", "paragraph:3-3", "heading:5-5" }, kinds)
    end)
  end)

  describe("setext headings", function()
    it("parses both levels with range over content and underline", function()
      local l, content, n = h({ "Foo", "===" })
      assert.equals(1, l)
      assert.equals("Foo", content)
      assert.equals(1, n.src_start)
      assert.equals(2, n.src_end)
      assert.equals(2, (h({ "Foo", "---" })))
      assert.equals(2, (h({ "Foo", "-" })))
    end)

    it("joins multi-line content into one heading", function()
      local l, content, n = h({ "Foo", "  Bar", "---" })
      assert.equals(2, l)
      assert.equals("Foo\nBar", content)
      assert.equals(3, n.src_end)
    end)

    it("takes up to 3 spaces of underline indent and trailing spaces", function()
      assert.equals(1, (h({ "Foo", "   ===  " })))
      local doc = block.parse({ "Foo", "    ===" })
      assert.equals("paragraph", doc.children[1].kind)
    end)

    it("rejects inner spaces in the underline", function()
      assert.is_nil((h({ "Foo", "= =" })))
    end)

    it("needs an open paragraph", function()
      local doc = block.parse({ "===" })
      assert.equals("paragraph", doc.children[1].kind)
      doc = block.parse({ "a", "", "===" })
      assert.equals("paragraph", doc.children[2].kind)
    end)

    it("lets an ATX line interrupt before the underline", function()
      local doc = block.parse({ "Foo", "# Bar", "===" })
      assert.equals("paragraph", doc.children[1].kind)
      assert.equals("heading", doc.children[2].kind)
      assert.equals("paragraph", doc.children[3].kind)
    end)

    it("starts a new paragraph after the heading", function()
      local doc = block.parse({ "Foo", "===", "bar" })
      assert.equals("heading", doc.children[1].kind)
      assert.equals("paragraph", doc.children[2].kind)
      assert.equals(3, doc.children[2].src_start)
    end)
  end)

  it("expand_indent counts columns with tab stop 4", function()
    assert.equals(4, (block.expand_indent("\tx")))
    assert.equals(4, (block.expand_indent("  \tx")))
    assert.equals(3, (block.expand_indent("   x")))
    assert.equals(0, (block.expand_indent("x")))
  end)

  it("parses inline content in paragraphs and headings", function()
    local doc = block.parse({ "a *b* ", "c", "", "# x `y`" })
    assert.same(
      { "text", "emph", "softbreak", "text" },
      vim.tbl_map(function(n)
        return n.kind
      end, doc.children[1].inlines)
    )
    assert.equals("code", doc.children[2].inlines[2].kind)
  end)

  it("keeps two trailing spaces as a hard break", function()
    local doc = block.parse({ "a  ", "b" })
    assert.equals("hardbreak", doc.children[1].inlines[2].kind)
  end)

  describe("thematic breaks", function()
    local function kinds(lines)
      return vim.tbl_map(function(b)
        return b.kind
      end, block.parse(lines).children)
    end

    it("accepts all three chars and spaced variants", function()
      for _, l in ipairs({
        "***",
        "---",
        "___",
        "* * *",
        "- - -",
        "_ _ _",
        "-----",
        " - - - ",
        "-\t-\t-",
      }) do
        assert.same({ "thematic_break" }, kinds({ l }), l)
      end
    end)

    it("rejects 2 chars, mixed chars and trailing text", function()
      for _, l in ipairs({ "**", "__", "**-", "-*-", "*** a", "--- a", "_ _ x" }) do
        assert.same({ "paragraph" }, kinds({ l }), l)
      end
    end)

    it("allows indent 0-3 but not 4", function()
      assert.same({ "thematic_break" }, kinds({ "   ***" }))
      assert.same({ "code_block" }, kinds({ "    ***" }))
    end)

    it("records the source range and validates", function()
      local doc = block.parse({ "a", "", "***" })
      assert.is_true(model.validate(doc))
      assert.equals(3, doc.children[2].src_start)
      assert.equals(3, doc.children[2].src_end)
    end)

    it("interrupts a paragraph", function()
      local doc = block.parse({ "a", "***", "b" })
      assert.same({ "paragraph", "thematic_break", "paragraph" }, kinds({ "a", "***", "b" }))
      assert.equals(1, doc.children[1].src_end)
    end)

    it("keeps setext precedence for plain dash runs", function()
      assert.same({ "heading" }, kinds({ "Foo", "---" }))
      assert.same({ "heading" }, kinds({ "Foo", "--" }))
      assert.same({ "heading" }, kinds({ "Foo", "===" }))
    end)

    it("makes spaced runs under a paragraph rules", function()
      assert.same({ "paragraph", "thematic_break" }, kinds({ "Foo", "- - -" }))
      assert.same({ "paragraph", "thematic_break" }, kinds({ "Foo", "* * *" }))
    end)

    it("treats --- without an open paragraph as a rule", function()
      assert.same({ "paragraph", "thematic_break" }, kinds({ "a", "", "---" }))
      assert.same({ "thematic_break", "thematic_break" }, kinds({ "---", "---" }))
      assert.same({ "heading", "thematic_break" }, kinds({ "Foo", "---", "---" }))
      assert.same({ "heading", "thematic_break" }, kinds({ "# h", "---" }))
    end)

    it("never treats === as a rule", function()
      assert.same({ "paragraph" }, kinds({ "===" }))
    end)
  end)

  describe("block quotes", function()
    -- Compact shape: quote -> {children}, others -> their kind (+ text).
    local function shape(node)
      if node.kind == "blockquote" then
        local t = {}
        for _, c in ipairs(node.children) do
          t[#t + 1] = shape(c)
        end
        return t
      elseif node.kind == "paragraph" or node.kind == "heading" then
        return node.kind:sub(1, 1) .. ":" .. plain(node.inlines)
      end
      return node.kind
    end

    local function q(lines)
      local doc = block.parse(lines)
      assert.is_true(model.validate(doc))
      local t = {}
      for _, c in ipairs(doc.children) do
        t[#t + 1] = shape(c)
      end
      return t, doc
    end

    local function range(n)
      return { n.src_start, n.src_end }
    end

    it("parses single and multi-line quotes", function()
      assert.same({ { "p:a" } }, (q({ "> a" })))
      assert.same({ { "p:a\nb" } }, (q({ "> a", "> b" })))
    end)

    it("accepts > with and without a space and 0-3 spaces of indent", function()
      assert.same({ { "p:a" } }, (q({ ">a" })))
      assert.same({ { "p:a" } }, (q({ "   > a" })))
      assert.equals("code_block", block.parse({ "    > a" }).children[1].kind)
    end)

    it("counts a tab after > as the optional space", function()
      assert.same({ { "p:a" } }, (q({ ">\ta" })))
    end)

    it("splits paragraphs on an empty > line", function()
      assert.same({ { "p:a", "p:b" } }, (q({ "> a", ">", "> b" })))
    end)

    it("ends the quote at a blank line", function()
      assert.same({ { "p:a" }, { "p:b" } }, (q({ ">a", "", ">b" })))
    end)

    it("continues a paragraph lazily", function()
      local t, doc = q({ "> a", "b" })
      assert.same({ { "p:a\nb" } }, t)
      assert.same({ 1, 2 }, range(doc.children[1]))
      assert.same({ 1, 2 }, range(doc.children[1].children[1]))
    end)

    it("does not continue lazily after a blank > line, heading or rule", function()
      assert.same({ { "p:a" }, "p:b" }, (q({ "> a", ">", "b" })))
      assert.same({ { "h:h" }, "p:b" }, (q({ "> # h", "b" })))
      assert.same({ { "thematic_break" }, "p:b" }, (q({ "> ---", "b" })))
    end)

    it("treats === after a quoted paragraph as lazy text", function()
      assert.same({ { "p:a\n===" } }, (q({ "> a", "===" })))
    end)

    it("makes --- after a quote a rule and # a heading closing the quote", function()
      assert.same({ { "p:a" }, "thematic_break" }, (q({ "> a", "---" })))
      assert.same({ { "p:a" }, "h:b" }, (q({ "> a", "# b" })))
    end)

    it("keeps a rule inside a quote a rule, an underline under a quoted paragraph", function()
      assert.same({ { "p:a", "thematic_break" } }, (q({ "> a", ">", "> ---" })))
      assert.same({ { "h:a" } }, (q({ "> a", "> ---" })))
    end)

    it("nests quotes", function()
      assert.same({ { { "p:a" } } }, (q({ "> > a" })))
      assert.same({ { { "p:a" } } }, (q({ ">> a" })))
      assert.same({ { { "p:a\nb\nc" } } }, (q({ "> > a", "> b", "c" })))
    end)

    it("lets a quote interrupt a paragraph", function()
      assert.same({ "p:a", { "p:b" } }, (q({ "a", "> b" })))
    end)

    it("holds headings, paragraphs and rules", function()
      assert.same({ { "h:h", "p:p", "thematic_break" } }, (q({ "> # h", ">", "> p", "> ***" })))
    end)

    it("keeps real source ranges", function()
      local doc = block.parse({ "x", "", "> a", "> b", ">", "> # h", "z" })
      local quote = doc.children[2]
      assert.same({ 3, 6 }, range(quote))
      assert.same({ 3, 4 }, range(quote.children[1]))
      assert.same({ 6, 6 }, range(quote.children[2]))
      assert.same({ 7, 7 }, range(doc.children[3]))
    end)

    it("keeps ranges in nested quotes", function()
      local doc = block.parse({ "> > a", "> b", "c" })
      assert.same({ 1, 3 }, range(doc.children[1].children[1].children[1]))
    end)

    it("resolves a definition inside a quote outside it", function()
      local doc = block.parse({ "[x]", "", "> [x]: http://e.com", "", "[x]" })
      assert.equals("link", doc.children[1].inlines[1].kind)
      assert.equals("link", doc.children[3].inlines[1].kind)
    end)

    it("scans a fence inside a quote as code", function()
      assert.same({ { "code_block" } }, (q({ "> ```" })))
    end)
  end)
  describe("lists (single level)", function()
    -- One list -> { ordered, start, item texts... } where an item is the
    -- plain text of its first paragraph.
    local function lists(lines)
      local doc = block.parse(lines)
      assert.is_true(model.validate(doc))
      return doc
    end

    local function items_of(list)
      local t = {}
      for _, it in ipairs(list.children) do
        local first = it.children[1]
        t[#t + 1] = first and first.kind == "paragraph" and plain(first.inlines)
          or (first and first.kind or "")
      end
      return t
    end

    local function range(n)
      return { n.src_start, n.src_end }
    end

    it("parses each bullet marker", function()
      for _, m in ipairs({ "-", "+", "*" }) do
        local doc = lists({ m .. " a", m .. " b" })
        assert.equals(1, #doc.children)
        assert.equals("list", doc.children[1].kind)
        assert.is_false(doc.children[1].ordered)
        assert.same({ "a", "b" }, items_of(doc.children[1]))
      end
    end)

    it("parses ordered markers with . and )", function()
      for _, d in ipairs({ ".", ")" }) do
        local list = lists({ "1" .. d .. " a", "2" .. d .. " b" }).children[1]
        assert.is_true(list.ordered)
        assert.equals(1, list.start)
        assert.same({ "a", "b" }, items_of(list))
      end
    end)

    it("takes the start number from the first item", function()
      assert.equals(0, lists({ "0. a" }).children[1].start)
      assert.equals(3, lists({ "3. a", "4. b" }).children[1].start)
    end)

    it("does not accept ten digits as a marker", function()
      assert.equals("paragraph", lists({ "1234567890. a" }).children[1].kind)
      assert.equals("list", lists({ "123456789. a" }).children[1].kind)
    end)

    it("allows 0-3 columns of indent, not 4", function()
      assert.equals("list", lists({ "   - a" }).children[1].kind)
      assert.equals("code_block", lists({ "    - a" }).children[1].kind)
    end)

    it("needs a space after the marker", function()
      assert.equals("paragraph", lists({ "-a" }).children[1].kind)
      assert.equals("paragraph", lists({ "1.a" }).children[1].kind)
    end)

    it("uses 1-4 spaces as content column, 5 as indented code start", function()
      assert.same({ "a" }, items_of(lists({ "-    a" }).children[1]))
      local item = lists({ "-     a" }).children[1].children[1]
      assert.equals("code_block", item.children[1].kind)
      assert.same({ "a" }, item.children[1].lines)
    end)

    it("makes an empty item", function()
      local list = lists({ "-", "- a" }).children[1]
      assert.same({ "", "a" }, items_of(list))
      assert.equals(0, #list.children[1].children)
      assert.same({ 1, 1 }, range(list.children[1]))
    end)

    it("starts a new list when the bullet changes", function()
      local doc = lists({ "- a", "+ b", "* c" })
      assert.equals(3, #doc.children)
    end)

    it("starts a new list when the delimiter changes", function()
      assert.equals(2, #lists({ "1. a", "2) b" }).children)
    end)

    it("lets 1. but not 2. interrupt a paragraph", function()
      assert.equals(2, #lists({ "p", "1. a" }).children)
      assert.same({ "paragraph" }, { lists({ "p", "2. a" }).children[1].kind })
      assert.equals(1, #lists({ "p", "2. a" }).children)
    end)

    it("lets a bullet but not an empty item interrupt a paragraph", function()
      assert.equals("list", lists({ "p", "- a" }).children[2].kind)
      assert.equals(1, #lists({ "p", "-" }).children)
      assert.equals("heading", lists({ "p", "-" }).children[1].kind)
      assert.equals(1, #lists({ "p", "1." }).children)
    end)

    it("continues a paragraph lazily", function()
      local list = lists({ "- a", "b" }).children[1]
      assert.same({ "a\nb" }, items_of(list))
    end)

    it("continues an item by indent", function()
      local item = lists({ "- a", "  b" }).children[1].children[1]
      assert.equals("a\nb", plain(item.children[1].inlines))
    end)

    it("keeps a blank line then an indented line in the item", function()
      local doc = lists({ "- a", "", "  b" })
      assert.equals(1, #doc.children)
      local item = doc.children[1].children[1]
      assert.equals(2, #item.children)
      assert.same({ 1, 3 }, range(item))
    end)

    it("ends the item at a less indented line after a blank", function()
      local doc = lists({ "- a", "", "b" })
      assert.equals(2, #doc.children)
      assert.equals("paragraph", doc.children[2].kind)
    end)

    it("ends an empty item at a blank line", function()
      local doc = lists({ "-", "", "  a" })
      assert.equals(2, #doc.children)
    end)

    it("keeps thematic breaks out of lists", function()
      assert.equals("thematic_break", lists({ "* * *" }).children[1].kind)
      assert.equals("thematic_break", lists({ "- - -" }).children[1].kind)
      local doc = lists({ "- a", "* * *" })
      assert.same({ "list", "thematic_break" }, { doc.children[1].kind, doc.children[2].kind })
    end)

    it("keeps a lone - after a paragraph as setext underline", function()
      local doc = lists({ "p", "-" })
      assert.equals(2, doc.children[1].level)
    end)

    it("keeps source ranges of list, items and children", function()
      local doc = lists({ "x", "", "- a", "  b", "- c", "", "  d" })
      local list = doc.children[2]
      assert.same({ 3, 7 }, range(list))
      assert.same({ 3, 4 }, range(list.children[1]))
      assert.same({ 3, 4 }, range(list.children[1].children[1]))
      assert.same({ 5, 7 }, range(list.children[2]))
      assert.same({ 5, 5 }, range(list.children[2].children[1]))
      assert.same({ 7, 7 }, range(list.children[2].children[2]))
    end)

    it("resolves a definition inside an item outside it", function()
      local doc = lists({ "[x]", "", "- [x]: http://e.com", "", "[x]" })
      assert.equals("link", doc.children[1].inlines[1].kind)
      assert.equals("link", doc.children[3].inlines[1].kind)
    end)

    it("does not crash on a quote and a list in each other", function()
      assert.is_true(model.validate(block.parse({ "> - a", "> - b", "- > c" })))
    end)
  end)

  describe("lists (nesting, tight/loose, tasks)", function()
    local function parse(lines)
      local doc = block.parse(lines)
      assert.is_true(model.validate(doc))
      return doc
    end

    local function range(n)
      return { n.src_start, n.src_end }
    end

    -- Shape string: list(item(...)) / quote(...) / p:text.
    local function shape(n)
      if n.kind == "paragraph" then
        return "p:" .. plain(n.inlines)
      elseif n.kind == "list_item" then
        local box = n.checked == nil and "" or (n.checked and "x" or "o")
        local t = {}
        for _, c in ipairs(n.children) do
          t[#t + 1] = shape(c)
        end
        return "i" .. box .. "(" .. table.concat(t, ",") .. ")"
      end
      local t = {}
      for _, c in ipairs(n.children or {}) do
        t[#t + 1] = shape(c)
      end
      return n.kind .. "(" .. table.concat(t, ",") .. ")"
    end

    local function doc_shape(lines)
      local t = {}
      for _, c in ipairs(parse(lines).children) do
        t[#t + 1] = shape(c)
      end
      return table.concat(t, " ")
    end

    it("nests a bullet in a bullet", function()
      assert.equals("list(i(p:a,list(i(p:b))))", doc_shape({ "- a", "  - b" }))
    end)

    it("nests an ordered list in a bullet", function()
      local list = parse({ "- a", "  1. b" }).children[1]
      assert.is_true(list.children[1].children[2].ordered)
    end)

    it("nests three levels", function()
      assert.equals(
        "list(i(p:a,list(i(p:b,list(i(p:c))))))",
        doc_shape({ "- a", "  - b", "    - c" })
      )
    end)

    it("does not nest below the content column", function()
      assert.equals("list(i(p:a),i(p:b))", doc_shape({ "- a", " - b" }))
    end)

    it("takes a sibling after a nested list", function()
      assert.equals("list(i(p:a,list(i(p:b))),i(p:c))", doc_shape({ "- a", "  - b", "- c" }))
    end)

    it("dedents two levels", function()
      assert.equals(
        "list(i(p:a,list(i(p:b,list(i(p:c))))),i(p:d))",
        doc_shape({ "- a", "  - b", "    - c", "- d" })
      )
    end)

    it("nests on the same line", function()
      assert.equals("list(i(list(i(p:a))))", doc_shape({ "1. - a" }))
    end)

    it("is tight without blank lines", function()
      assert.is_true(parse({ "- a", "- b" }).children[1].tight)
    end)

    it("is loose with a blank line between items", function()
      assert.is_false(parse({ "- a", "", "- b" }).children[1].tight)
    end)

    it("is loose with a blank line between item children", function()
      assert.is_false(parse({ "- a", "", "  b", "- c" }).children[1].tight)
    end)

    it("keeps the outer list tight when only a nested list is loose", function()
      local outer = parse({ "- a", "  - b", "", "  - c", "- d" }).children[1]
      assert.is_true(outer.tight)
      assert.is_false(outer.children[1].children[2].tight)
    end)

    it("stays tight with a trailing blank line", function()
      assert.is_true(parse({ "- a", "- b", "" }).children[1].tight)
      assert.is_true(parse({ "- a", "  - b", "" }).children[1].tight)
    end)

    it("ends the list at a blank line and an unindented paragraph", function()
      assert.equals("list(i(p:a)) p:b", doc_shape({ "- a", "", "b" }))
    end)

    it("ends the list at a non-lazy less indented line", function()
      assert.equals("list(i(p:a)) heading()", doc_shape({ "- a", "# h" }))
    end)

    it("makes two lists when the marker changes across blank lines", function()
      assert.equals("list(i(p:a)) list(i(p:b))", doc_shape({ "- a", "", "+ b" }))
    end)

    it("puts a list in a quote", function()
      assert.equals("blockquote(list(i(p:a),i(p:b)))", doc_shape({ "> - a", "> - b" }))
    end)

    it("puts a quote in a list", function()
      assert.equals("list(i(blockquote(p:a)))", doc_shape({ "- > a" }))
      assert.equals("list(i(p:a,blockquote(p:b)))", doc_shape({ "- a", "  > b" }))
    end)

    it("reads task boxes", function()
      assert.equals("list(io(p:a),ix(p:b),ix(p:c))", doc_shape({ "- [ ] a", "- [x] b", "- [X] c" }))
    end)

    it("reads a box with no text and a box in a nested item", function()
      assert.equals("list(io(),i(p:a,list(ix(p:b))))", doc_shape({ "- [ ]", "- a", "  - [x] b" }))
    end)

    it("keeps non-task boxes as text", function()
      assert.equals("list(i(p:[] a))", doc_shape({ "- [] a" }))
      assert.equals("list(i(p:[xx] a))", doc_shape({ "- [xx] a" }))
      assert.equals("list(i(p:[ x] a))", doc_shape({ "- [ x] a" }))
      assert.equals("list(i(p:a [ ] b))", doc_shape({ "- a [ ] b" }))
      assert.equals("list(i(p:[x]a))", doc_shape({ "- [x]a" }))
    end)

    it("only reads a box in the first paragraph", function()
      assert.equals("list(i(p:a,p:[x] b))", doc_shape({ "- a", "", "  [x] b" }))
    end)

    it("keeps source ranges at every level", function()
      local doc = parse({ "p", "", "- a", "  - b", "    c", "- d" })
      local list = doc.children[2]
      assert.same({ 3, 6 }, range(list))
      local item = list.children[1]
      assert.same({ 3, 5 }, range(item))
      local nested = item.children[2]
      assert.same({ 4, 5 }, range(nested))
      assert.same({ 4, 5 }, range(nested.children[1]))
      assert.same({ 4, 5 }, range(nested.children[1].children[1]))
      assert.same({ 6, 6 }, range(list.children[2]))
    end)

    it("does not crash on a fence or a table row in an item", function()
      assert.is_true(model.validate(block.parse({ "- ```", "  x", "  ```" })))
      assert.is_true(model.validate(block.parse({ "- | a | b |", "  | - | - |" })))
    end)
  end)

  describe("fenced code", function()
    local function code_of(lines)
      local doc = block.parse(lines)
      assert.is_true(model.validate(doc))
      return doc, doc.children[1]
    end

    it("parses backtick and tilde fences", function()
      local _, c = code_of({ "```", "a", "b", "```" })
      assert.equals("code_block", c.kind)
      assert.same({ "a", "b" }, c.lines)
      assert.is_nil(c.lang)
      _, c = code_of({ "~~~", "a", "~~~" })
      assert.same({ "a" }, c.lines)
    end)

    it("allows longer fences and needs an equal or longer closer", function()
      local doc, c = code_of({ "````", "a", "```", "~~~~", "````", "b" })
      assert.same({ "a", "```", "~~~~" }, c.lines)
      assert.equals(2, #doc.children)
      local _
      _, c = code_of({ "```", "a", "`````" })
      assert.same({ "a" }, c.lines)
      _, c = code_of({ "~~~", "a", "```", "~~~" })
      assert.same({ "a", "```" }, c.lines)
    end)

    it("closes with 0-3 columns of indent but not 4", function()
      local doc, c = code_of({ "```", "a", "   ```", "b" })
      assert.same({ "a" }, c.lines)
      assert.equals(2, #doc.children)
      local _
      _, c = code_of({ "```", "a", "    ```" })
      assert.same({ "a", "    ```" }, c.lines)
    end)

    it("does not close with text after the closer", function()
      local _, c = code_of({ "```", "a", "``` x", "```  " })
      assert.same({ "a", "``` x" }, c.lines)
    end)

    it("takes the first info word as lang", function()
      assert.equals("lua", select(2, code_of({ "```lua", "```" })).lang)
      assert.equals("lua", select(2, code_of({ "``` lua {a=1} b", "```" })).lang)
      assert.equals("c++", select(2, code_of({ "~~~ c\\+\\+", "~~~" })).lang)
      assert.equals("f\u{f6}", select(2, code_of({ "```f&ouml;", "```" })).lang)
      assert.is_nil(select(2, code_of({ "```   ", "```" })).lang)
    end)

    it("does not open a backtick fence whose info has a backtick", function()
      local _, p = code_of({ "``` a`b", "x" })
      assert.equals("paragraph", p.kind)
      _, p = code_of({ "~~~ a`b", "x", "~~~" })
      assert.equals("code_block", p.kind)
      assert.equals("a`b", p.lang)
    end)

    it("strips up to the opener indent", function()
      local _, c = code_of({ " ```", "  a", " b", "c", "   ```" })
      assert.same({ " a", "b", "c" }, c.lines)
      _, c = code_of({ "   ~~~", "  a", "    b", "~~~" })
      assert.same({ "a", " b" }, c.lines)
    end)

    it("does not open with 4 spaces of indent", function()
      local doc, c = code_of({ "    ```", "a" })
      assert.same({ "```" }, c.lines)
      assert.equals("paragraph", doc.children[2].kind)
    end)

    it("runs an unclosed fence to the end", function()
      local doc = code_of({ "p", "", "```", "a", "", "b" })
      local c = doc.children[2]
      assert.same({ "a", "", "b" }, c.lines)
      assert.same({ 3, 6, 4 }, { c.src_start, c.src_end, c.src_body })
    end)

    it("handles an empty fence", function()
      local _, c = code_of({ "```", "```" })
      assert.same({}, c.lines)
      _, c = code_of({ "```" })
      assert.same({}, c.lines)
    end)

    it("keeps blank lines inside", function()
      local _, c = code_of({ "```", "", "a", "", "", "```" })
      assert.same({ "", "a", "", "" }, c.lines)
    end)

    it("keeps block syntax inside raw", function()
      local lines = { "# h", "---", "> q", "- i", "[a]: /u", "1. x", "===" }
      local all = { "```" }
      for _, l in ipairs(lines) do
        all[#all + 1] = l
      end
      all[#all + 1] = "```"
      local doc, c = code_of(all)
      assert.equals(1, #doc.children)
      assert.same(lines, c.lines)
    end)

    it("interrupts a paragraph", function()
      local doc = block.parse({ "a", "```", "x", "```", "b" })
      assert.same({ "paragraph", "code_block", "paragraph" }, {
        doc.children[1].kind,
        doc.children[2].kind,
        doc.children[3].kind,
      })
      assert.same({ 1, 1 }, { doc.children[1].src_start, doc.children[1].src_end })
    end)

    it("treats --- after a paragraph as setext, then a fence", function()
      local doc = block.parse({ "a", "---", "```", "x", "```" })
      assert.equals("heading", doc.children[1].kind)
      assert.equals("code_block", doc.children[2].kind)
    end)

    it("reports source ranges below line 1", function()
      local doc = block.parse({ "a", "", "b", "", "  ```js", "  x", "  ```", "", "c" })
      local c = doc.children[3]
      assert.same({ 5, 7, 6 }, { c.src_start, c.src_end, c.src_body })
      assert.same({ 9, 9 }, { doc.children[4].src_start, doc.children[4].src_end })
    end)

    it("does not take a definition inside a fence", function()
      local doc = block.parse({ "```", "[a]: /u", "```", "", "[a]" })
      assert.equals("code_block", doc.children[1].kind)
      assert.same({ "[a]: /u" }, doc.children[1].lines)
      assert.equals("paragraph", doc.children[2].kind)
      assert.equals("text", doc.children[2].inlines[1].kind)
    end)
  end)

  describe("indented code", function()
    local function parse(lines)
      local doc = block.parse(lines)
      assert.is_true(model.validate(doc))
      return doc
    end

    it("parses 4 spaces and a tab", function()
      local c = parse({ "    a", "\tb" }).children[1]
      assert.equals("code_block", c.kind)
      assert.same({ "a", "b" }, c.lines)
      assert.is_nil(c.lang)
    end)

    it("keeps extra indent beyond 4 columns", function()
      assert.same({ " a", "  b" }, parse({ "     a", "      b" }).children[1].lines)
    end)

    it("keeps interior blanks and drops trailing ones", function()
      local doc = parse({ "    a", "", "      ", "    b", "", "c" })
      local c = doc.children[1]
      assert.same({ "a", "", "  ", "b" }, c.lines)
      assert.same({ 1, 4, 1 }, { c.src_start, c.src_end, c.src_body })
      assert.equals("paragraph", doc.children[2].kind)
      assert.same({ 6, 6 }, { doc.children[2].src_start, doc.children[2].src_end })
    end)

    it("ends at an unindented line", function()
      local doc = parse({ "    a", "b" })
      assert.equals("code_block", doc.children[1].kind)
      assert.equals("paragraph", doc.children[2].kind)
    end)

    it("is a paragraph continuation after a paragraph", function()
      local doc = parse({ "a", "    b" })
      assert.equals(1, #doc.children)
      assert.equals("paragraph", doc.children[1].kind)
    end)

    it("is code after a heading and after a rule", function()
      local doc = parse({ "# h", "    a", "***", "    b" })
      assert.same({ "heading", "code_block", "thematic_break", "code_block" }, {
        doc.children[1].kind,
        doc.children[2].kind,
        doc.children[3].kind,
        doc.children[4].kind,
      })
    end)

    it("takes #, - and > after 4 spaces as code text", function()
      local c = parse({ "    # a", "    - b", "    > c", "    ---" }).children[1]
      assert.same({ "# a", "- b", "> c", "---" }, c.lines)
    end)

    it("reports ranges below line 1", function()
      local doc = parse({ "a", "", "    x", "    y", "", "b" })
      local c = doc.children[2]
      assert.same({ 3, 4, 3 }, { c.src_start, c.src_end, c.src_body })
    end)

    it("does not take a definition", function()
      local doc = parse({ "    [a]: /u", "", "[a]" })
      assert.same({ "[a]: /u" }, doc.children[1].lines)
      assert.equals("text", doc.children[2].inlines[1].kind)
    end)
  end)

  describe("code in containers", function()
    local function parse(lines)
      return block.parse(lines)
    end

    local function code_of(c)
      return { c.kind, c.lines and table.concat(c.lines, "|"), c.src_start, c.src_end, c.src_body }
    end

    it("takes a closed fence in a quote", function()
      local q = parse({ "> ```", "> code", "> ```" }).children[1]
      assert.same({ "code_block", "code", 1, 3, 2 }, code_of(q.children[1]))
      assert.same({ 1, 3 }, { q.src_start, q.src_end })
    end)

    it("ends an unclosed quote fence with the quote; a lazy line is no code", function()
      local doc = parse({ "> ```", "> code", "lazy" })
      assert.equals("blockquote", doc.children[1].kind)
      assert.same({ "code_block", "code", 1, 2, 2 }, code_of(doc.children[1].children[1]))
      assert.equals("paragraph", doc.children[2].kind)
      assert.equals(3, doc.children[2].src_start)
    end)

    it("takes indented code in a quote", function()
      local q = parse({ ">     a", "> b" }).children[1]
      assert.same({ "code_block", "a", 1, 1, 1 }, code_of(q.children[1]))
      assert.equals("paragraph", q.children[2].kind)
    end)

    it("takes a fence in an item, also on the marker line", function()
      local doc = parse({ "- ```", "  a", "  ```", "", "1. ```", "   b", "   ```" })
      local c1 = doc.children[1].children[1].children[1]
      local c2 = doc.children[2].children[1].children[1]
      assert.same({ "code_block", "a", 1, 3, 2 }, code_of(c1))
      assert.same({ "code_block", "b", 5, 7, 6 }, code_of(c2))
    end)

    it("strips a fence's own indent inside an item", function()
      local item = parse({ "- a", "  ```", "   x", "  ```" }).children[1].children[1]
      assert.same({ " x" }, item.children[2].lines)
    end)

    it("keeps a blank line inside an item fence and stays tight", function()
      local list = parse({ "- a", "  ```", "  x", "", "  y", "  ```", "- b" }).children[1]
      assert.same({ "x", "", "y" }, list.children[1].children[2].lines)
      assert.is_true(list.tight)
      assert.same({ 1, 6 }, { list.children[1].src_start, list.children[1].src_end })
    end)

    it("ends the fence when a less indented line ends the item", function()
      local doc = parse({ "- ```", "  a", "b" })
      assert.same({ "code_block", "a", 1, 2, 2 }, code_of(doc.children[1].children[1].children[1]))
      assert.equals("paragraph", doc.children[2].kind)
    end)

    it("takes a 5-space marker item as indented code", function()
      local item = parse({ "-     a" }).children[1].children[1]
      assert.same({ "code_block", "a", 1, 1, 1 }, code_of(item.children[1]))
    end)

    it("takes indented code in an item after a blank, loose", function()
      local list = parse({ "- a", "", "      b" }).children[1]
      assert.is_false(list.tight)
      assert.same({ "code_block", "b", 3, 3, 3 }, code_of(list.children[1].children[2]))
    end)

    it("is loose when a blank line comes before the fence", function()
      local list = parse({ "- a", "", "  ```", "  x", "  ```" }).children[1]
      assert.is_false(list.tight)
    end)

    it("takes a fence in a nested item", function()
      local inner =
        parse({ "- - ```", "    x", "    ```", "  - y" }).children[1].children[1].children[1]
      assert.same({ "code_block", "x", 1, 3, 2 }, code_of(inner.children[1].children[1]))
      assert.equals(2, #inner.children)
    end)

    it("takes a quote with a fence inside an item", function()
      local q = parse({ "- > ```", "  > x", "  > ```" }).children[1].children[1].children[1]
      assert.equals("blockquote", q.kind)
      assert.same({ "code_block", "x", 1, 3, 2 }, code_of(q.children[1]))
    end)

    it("does not crash on a fence in a quote in a list", function()
      local doc = parse({ "- > ```", "  > x", "- b" })
      assert.equals(1, #doc.children)
      assert.equals(2, #doc.children[1].children)
    end)

    it("ends a quote at an unindented fence opener (not a lazy line)", function()
      local doc = parse({ "> a", "```", "b", "```" })
      assert.equals("blockquote", doc.children[1].kind)
      assert.equals("code_block", doc.children[2].kind)
    end)

    it("ends an item at an unindented fence opener (not a lazy line)", function()
      local doc = parse({ "- a", "```", "b", "```" })
      assert.equals("list", doc.children[1].kind)
      assert.equals("code_block", doc.children[2].kind)
    end)
  end)
end)

describe("markdown.block html blocks", function()
  local function parse(lines)
    local doc = block.parse(lines)
    assert.is_true(model.validate(doc))
    return doc.children
  end

  local function html_of(lines)
    local c = parse(lines)
    assert.equals(1, #c)
    assert.equals("html_block", c[1].kind)
    return c[1]
  end

  it("condition 1 runs through the closing tag, blank lines inside", function()
    local h = html_of({ "<pre>", "", "# x", "</PRE>" })
    assert.same({ "<pre>", "", "# x", "</PRE>" }, h.lines)
    assert.equals(1, h.src_start)
    assert.equals(4, h.src_end)
    h = html_of({ "<script>a</script> tail" })
    assert.same({ "<script>a</script> tail" }, h.lines)
    html_of({ "<STYLE", "x" })
    html_of({ "<textarea>" })
  end)

  it("conditions 2 to 5 end at their marker, start line included", function()
    assert.same({ "<!-- a", "", "b -->" }, html_of({ "<!-- a", "", "b -->" }).lines)
    assert.equals(1, #html_of({ "<!-- a -->" }).lines)
    assert.same({ "<?php", "x ?>" }, html_of({ "<?php", "x ?>" }).lines)
    assert.same({ "<!DOCTYPE", "html>" }, html_of({ "<!DOCTYPE", "html>" }).lines)
    assert.same({ "<![CDATA[", "", "x]]>" }, html_of({ "<![CDATA[", "", "x]]>" }).lines)
    local c = parse({ "<!-- a -->", "text" })
    assert.equals("html_block", c[1].kind)
    assert.equals("paragraph", c[2].kind)
    assert.equals(2, c[2].src_start)
  end)

  it("condition 6 ends before the blank line", function()
    local c = parse({ "<div>", "# x", "- y", "", "p" })
    assert.same({ "<div>", "# x", "- y" }, c[1].lines)
    assert.equals("paragraph", c[2].kind)
    for _, l in ipairs({ "</div>", "<div/>", "<div />", "<DIV class=x", "<div", "<p>" }) do
      assert.equals("html_block", parse({ l })[1].kind, l)
    end
    assert.equals("paragraph", parse({ "<divx> text" })[1].kind)
  end)

  it("condition 7 needs a complete tag alone on the line", function()
    html_of({ "<a href=\"x\" b='y' c=z d>" })
    html_of({ "  </span>  " })
    assert.same({ "<x-y/>", "text" }, html_of({ "<x-y/>", "text" }).lines)
    for _, l in ipairs({ '<a href="x', "<a> text", "<a b=>", "<a", "</a b>" }) do
      assert.equals("paragraph", parse({ l })[1].kind, l)
    end
  end)

  it("7 does not interrupt a paragraph, 1 to 6 do", function()
    local c = parse({ "para", "<span>" })
    assert.equals(1, #c)
    assert.equals("paragraph", c[1].kind)
    c = parse({ "para", "<div>", "x" })
    assert.equals("paragraph", c[1].kind)
    assert.equals("html_block", c[2].kind)
    assert.equals(2, c[2].src_start)
    assert.equals("html_block", parse({ "para", "<!-- c -->" })[2].kind)
  end)

  it("four spaces is indented code, one to three are kept", function()
    assert.equals("code_block", parse({ "    <div>" })[1].kind)
    assert.same({ "  <div>", "   x" }, html_of({ "  <div>", "   x" }).lines)
  end)

  it("keeps markdown inside raw", function()
    local h = html_of({ "<div>", "# h", "---", "> q", "```", "[a]: /u" })
    assert.equals(6, #h.lines)
  end)

  it("unclosed blocks run to the end; ranges at line > 1", function()
    local c = parse({ "a", "", "<!--", "x", "", "y" })
    assert.equals(2, #c)
    assert.equals(3, c[2].src_start)
    assert.equals(6, c[2].src_end)
    assert.equals(3, c[2].src_body)
    assert.equals(4, #c[2].lines)
  end)
end)

describe("markdown.block html blocks in containers", function()
  local function parse(lines)
    local doc = block.parse(lines)
    assert.is_true(model.validate(doc))
    return doc.children
  end

  it("block in a quote: prefix stripped, indent kept, closed or unclosed", function()
    local q = parse({ "> <div>", ">  x", "> </div>", "> after" })[1]
    assert.equals("blockquote", q.kind)
    assert.equals("html_block", q.children[1].kind)
    assert.same({ "<div>", " x", "</div>", "after" }, q.children[1].lines)
    q = parse({ "> <!-- a", ">", "> b -->", "> p" })[1]
    assert.same({ "<!-- a", "", "b -->" }, q.children[1].lines)
    assert.equals("paragraph", q.children[2].kind)
    assert.equals(4, q.children[2].src_start)
  end)

  it("a lazy line is never part of a quoted html block", function()
    local c = parse({ "> <div>", "lazy" })
    assert.equals(2, #c)
    assert.same({ "<div>" }, c[1].children[1].lines)
    assert.equals("paragraph", c[2].kind)
    c = parse({ "> <!-- a", "lazy" })
    assert.equals(2, #c)
    assert.equals(2, c[2].src_start)
  end)

  it("an unindented html start ends a quoted paragraph, condition 7 does not", function()
    local c = parse({ "> para", "<div>" })
    assert.equals("blockquote", c[1].kind)
    assert.equals("html_block", c[2].kind)
    c = parse({ "> para", "<span>" })
    assert.equals(1, #c)
    assert.equals(1, #c[1].children)
  end)

  it("block in bullet and ordered items", function()
    local it1 = parse({ "- <div>", "  x", "", "  y", "", "z" })
    assert.equals("list", it1[1].kind)
    local kids = it1[1].children[1].children
    assert.same({ "<div>", "x" }, kids[1].lines)
    assert.equals("paragraph", kids[2].kind)
    assert.equals("paragraph", it1[2].kind)
    local o = parse({ "1. <pre>", "   a", "", "   b", "   </pre>", "2. n" })[1]
    assert.same({ "<pre>", "a", "", "b", "</pre>" }, o.children[1].children[1].lines)
    assert.equals(2, #o.children)
  end)

  it("a less indented line closes the item and the block", function()
    local c = parse({ "- <!-- a", "", "b -->" })
    assert.equals("list", c[1].kind)
    assert.same({ "<!-- a" }, c[1].children[1].children[1].lines)
    assert.equals("paragraph", c[2].kind)
    c = parse({ "- <div>", "<p>x" })
    assert.equals("list", c[1].kind)
    assert.equals("html_block", c[2].kind)
  end)

  it("comment with blank lines inside an item; ranges", function()
    local l = parse({ "- <!--", "", "  x", "  -->", "- b" })[1]
    local h = l.children[1].children[1]
    assert.same({ "<!--", "", "x", "-->" }, h.lines)
    assert.equals(1, h.src_start)
    assert.equals(4, h.src_end)
    assert.equals(1, h.src_body)
    assert.equals(4, l.children[1].src_end)
    assert.is_true(l.tight)
  end)

  it("tight stays tight with a blank inside html, loose by blank before it", function()
    assert.is_true(parse({ "- a", "  <!-- x", "", "  y -->", "- b" })[1].tight)
    assert.is_false(parse({ "- a", "", "  <div>", "- b" })[1].tight)
  end)

  it("nested item and quote in item", function()
    local l = parse({ "- a", "  - <div>", "    x" })[1]
    local inner = l.children[1].children[2]
    assert.same({ "<div>", "x" }, inner.children[1].children[1].lines)
    local q = parse({ "- > <b>", "  > c" })[1].children[1].children[1]
    assert.equals("blockquote", q.kind)
    assert.same({ "<b>", "c" }, q.children[1].lines)
    local deep = parse({ "- > - <div>", "  >   x" })
    assert.equals("list", deep[1].kind)
  end)
end)

describe("markdown.block tables in containers", function()
  local function parse(lines)
    local doc = block.parse(lines)
    assert.is_true(model.validate(doc))
    return doc.children
  end

  it("parses a table in a block quote with source ranges", function()
    local c = parse({ "intro", "", "> a|b", "> -|-", "> 1|2", "> 3|4" })
    local t = c[2].children[1]
    assert.equals("table", t.kind)
    assert.equals(3, t.src_start)
    assert.equals(6, t.src_end)
    assert.equals(2, #t.rows)
    assert.equals(6, c[2].src_end)
  end)

  it("a lazy line ends the table; it becomes a paragraph", function()
    local c = parse({ "> a|b", "> -|-", "> 1|2", "lazy" })
    local q = c[1]
    assert.equals(3, q.src_end)
    assert.equals("table", q.children[1].kind)
    assert.equals(1, #q.children[1].rows)
    assert.equals(1, #q.children)
    assert.equals("paragraph", c[2].kind)
    assert.equals(4, c[2].src_start)
  end)

  it("a lazy delimiter does not start a table", function()
    local c = parse({ "> a|b", "-|-" })
    assert.equals("paragraph", c[1].children[1].kind)
  end)

  it("ends with the quote", function()
    local c = parse({ "> a|b", "> -|-", "", "x|y" })
    assert.equals("blockquote", c[1].kind)
    assert.equals(2, c[1].src_end)
    assert.equals("paragraph", c[2].kind)
  end)

  it("parses a table in a list item and continues on indented rows", function()
    local c = parse({ "- a|b", "  -|-", "  1|2", "- next" })
    local items = c[1].children
    local t = items[1].children[1]
    assert.equals("table", t.kind)
    assert.equals(1, t.src_start)
    assert.equals(3, t.src_end)
    assert.equals(1, #t.rows)
    assert.equals(2, #items)
    assert.is_true(c[1].tight)
  end)

  it("a less indented row line is not part of the item table", function()
    local c = parse({ "- a|b", "  -|-", "x|y" })
    local t = c[1].children[1].children[1]
    assert.equals(0, #t.rows)
    assert.equals(1, #c[1].children[1].children)
    assert.equals("paragraph", c[2].kind)
    assert.equals(3, c[2].src_start)
  end)

  it("a list item can follow header text on a later line", function()
    local c = parse({ "1. intro", "   a|b", "   -|-", "   1|2" })
    local ch = c[1].children[1].children
    assert.equals("paragraph", ch[1].kind)
    assert.equals("table", ch[2].kind)
    assert.equals(2, ch[2].src_start)
    assert.equals(4, ch[2].src_end)
  end)

  it("loose detection counts the table range", function()
    local tight = parse({ "- a|b", "  -|-", "  1|2", "  after" })
    assert.is_true(tight[1].tight)
    local loose = parse({ "- a|b", "  -|-", "  1|2", "", "  after" })
    assert.is_false(loose[1].tight)
    local items = parse({ "- a|b", "  -|-", "  1|2", "", "- two" })
    assert.is_false(items[1].tight)
  end)

  it("handles a table in a quote nested in a list", function()
    local c = parse({ "- > a|b", "  > -|-", "  > 1|2", "- two" })
    local q = c[1].children[1].children[1]
    assert.equals("blockquote", q.kind)
    assert.equals("table", q.children[1].kind)
    assert.equals(1, q.children[1].src_start)
    assert.equals(3, q.children[1].src_end)
    assert.equals(2, #c[1].children)
  end)

  it("handles a list inside a quote with a table in the item", function()
    local c = parse({ "> - a|b", ">   -|-", ">   1|2" })
    local t = c[1].children[1].children[1].children[1]
    assert.equals("table", t.kind)
    assert.equals(3, t.src_end)
  end)

  describe("lone image promotion", function()
    local function kids(lines)
      local doc = block.parse(lines)
      assert.is_true(model.validate(doc))
      return doc.children
    end

    local function assert_block(n, alt, target, title)
      assert.equals("image", n.kind)
      assert.is_true(n.block)
      assert.equals(alt, n.alt)
      assert.equals(target, n.target)
      assert.equals(title, n.title)
    end

    it("promotes a lone image, with title, reference and empty alt", function()
      local c = kids({ "![a](/u)" })
      assert.equals(1, #c)
      assert_block(c[1], "a", "/u")
      assert.equals(1, c[1].src_start)
      assert_block(kids({ '![a](/u "T")' })[1], "a", "/u", "T")
      assert_block(kids({ "![a][r]", "", "[r]: /ref" })[1], "a", "/ref")
      assert_block(kids({ "![](/u)" })[1], "", "/u")
    end)

    it("keeps the source range of a multi-line image", function()
      local c = kids({ "x", "", "![a", "b](/u)" })
      assert_block(c[2], "a b", "/u")
      assert.equals(3, c[2].src_start)
      assert.equals(4, c[2].src_end)
    end)

    it("promotes with surrounding spaces", function()
      assert_block(kids({ "   ![a](/u)   " })[1], "a", "/u")
    end)

    it("leaves other paragraphs alone", function()
      assert.equals("paragraph", kids({ "x ![a](/u)" })[1].kind)
      assert.equals("paragraph", kids({ "![a](/u) x" })[1].kind)
      assert.equals("paragraph", kids({ "![a](/u)![b](/v)" })[1].kind)
      assert.equals("paragraph", kids({ "[![a](/u)](/l)" })[1].kind)
      assert.equals("paragraph", kids({ "![a](/u)\\" })[1].kind)
      assert.equals("paragraph", kids({ "![a](/u)", "x" })[1].kind)
    end)

    it("does not promote inside a heading", function()
      local h = kids({ "# ![a](/u)" })[1]
      assert.equals("heading", h.kind)
      assert.equals("image", h.inlines[1].kind)
      assert.is_nil(h.inlines[1].block)
    end)

    it("promotes inside quotes and list items", function()
      assert_block(kids({ "> ![a](/u)" })[1].children[1], "a", "/u")
      local item = kids({ "- ![a](/u)" })[1].children[1]
      assert_block(item.children[1], "a", "/u")
    end)

    it("keeps a list tight with a lone-image item", function()
      local l = kids({ "- ![a](/u)", "- b" })[1]
      assert.is_true(l.tight)
      assert_block(l.children[1].children[1], "a", "/u")
    end)
  end)
end)
