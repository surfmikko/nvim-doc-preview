local model = require("doc_preview.document.model")
local block = require("doc_preview.markdown.block")

local function parse(lines)
  local doc = block.parse(lines)
  assert.is_true(model.validate(doc))
  return doc.children
end

local function kinds(nodes)
  local out = {}
  for i, n in ipairs(nodes) do
    out[i] = n.kind
  end
  return out
end

describe("markdown.block footnote definitions", function()
  it("parses a one-line definition", function()
    local c = parse({ "[^a]: Note." })
    assert.same({ "footnote_def" }, kinds(c))
    assert.equals("a", c[1].label)
    assert.same({ "paragraph" }, kinds(c[1].children))
    assert.equals("Note.", c[1].children[1].inlines[1].value)
    assert.equals(1, c[1].src_start)
    assert.equals(1, c[1].src_end)
  end)

  it("is not a link reference definition", function()
    local c = parse({ "[^x]: http://example.com", "", "[^x]" })
    assert.same({ "footnote_def", "paragraph" }, kinds(c))
    assert.equals("footnote_ref", c[2].inlines[1].kind)
  end)

  it("takes a multi-line paragraph body with 4-column continuation", function()
    local c = parse({ "[^a]: one", "    two" })
    assert.equals(1, #c)
    assert.equals(2, c[1].src_end)
    assert.equals(1, #c[1].children)
    assert.equals(2, c[1].children[1].src_end)
  end)

  it("takes an indented paragraph after a blank line", function()
    local c = parse({ "[^a]: one", "", "    two", "", "after" })
    assert.same({ "footnote_def", "paragraph" }, kinds(c))
    assert.equals(2, #c[1].children)
    assert.equals(3, c[1].src_end)
    assert.equals(3, c[1].children[2].src_start)
  end)

  it("continues lazily and ends at an unindented line after a blank", function()
    local c = parse({ "[^a]: one", "lazy", "", "next" })
    assert.same({ "footnote_def", "paragraph" }, kinds(c))
    assert.equals(2, c[1].src_end)
    assert.equals(4, c[2].src_start)
  end)

  it("holds a list and fenced code", function()
    local c =
      parse({ "[^a]: intro", "", "    - x", "    - y", "", "    ```lua", "    local a", "    ```" })
    assert.same({ "footnote_def" }, kinds(c))
    assert.same({ "paragraph", "list", "code_block" }, kinds(c[1].children))
    assert.equals(8, c[1].src_end)
    assert.equals(6, c[1].children[3].src_start)
  end)

  it("handles adjacent definitions", function()
    local c = parse({ "[^a]: one", "[^b]: two" })
    assert.same({ "footnote_def", "footnote_def" }, kinds(c))
    assert.equals("b", c[2].label)
    assert.equals(2, c[2].src_start)
  end)

  it("normalises the label case", function()
    assert.equals("abc", parse({ "[^AbC]: x" })[1].label)
  end)

  it("rejects empty and whitespace labels", function()
    -- Not footnotes; they fall through to link reference definitions.
    assert.same({}, kinds(parse({ "[^]: x" })))
    assert.same({}, kinds(parse({ "[^a b]: x" })))
    assert.same({ "paragraph" }, kinds(parse({ "[^a b]: x", "", "[^a b]" })))
  end)

  it("keeps both definitions of a duplicate label in the tree", function()
    local c = parse({ "[^a]: first", "", "[^a]: second" })
    assert.same({ "footnote_def", "footnote_def" }, kinds(c))
    assert.equals("first", c[1].children[1].inlines[1].value)
  end)

  it("needs indent 0-3", function()
    assert.same({ "code_block" }, kinds(parse({ "    [^a]: x" })))
    assert.same({ "footnote_def" }, kinds(parse({ "   [^a]: x" })))
  end)

  -- cmark-gfm does not exempt definitions from interrupting a paragraph.
  it("interrupts a paragraph", function()
    local c = parse({ "text", "[^a]: note" })
    assert.same({ "paragraph", "footnote_def" }, kinds(c))
    assert.equals(1, c[1].src_end)
    assert.equals(2, c[2].src_start)
  end)

  it("keeps source ranges below line 1", function()
    local c = parse({ "# h", "", "para", "", "[^a]: one", "    two" })
    assert.equals(5, c[3].src_start)
    assert.equals(6, c[3].src_end)
  end)

  it("works in a block quote and a list item", function()
    local q = parse({ "> [^a]: one", ">     two" })
    assert.same({ "footnote_def" }, kinds(q[1].children))
    assert.equals(2, q[1].children[1].src_end)
    local l = parse({ "- [^b]: one", "      two" })
    local item = l[1].children[1]
    assert.same({ "footnote_def" }, kinds(item.children))
    assert.equals(2, item.children[1].src_end)
  end)
end)
