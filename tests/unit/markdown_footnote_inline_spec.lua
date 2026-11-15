local block = require("doc_preview.markdown.block")

local function para(lines)
  local doc = block.parse(lines)
  for _, n in ipairs(doc.children) do
    if n.kind == "paragraph" then
      return n.inlines
    end
  end
end

local function kinds(inl)
  local out = {}
  for i, n in ipairs(inl) do
    out[i] = n.kind == "footnote_ref" and ("ref:" .. n.label) or n.kind
  end
  return out
end

local function with_def(text, label)
  return para({ text, "", "[^" .. (label or "x") .. "]: Note." })
end

describe("markdown.inline footnote references", function()
  it("turns a defined reference into footnote_ref", function()
    local i = with_def("a[^x]b")
    assert.same({ "text", "ref:x", "text" }, kinds(i))
    assert.equals("a", i[1].value)
    assert.equals("b", i[3].value)
  end)

  it("works between emphasis", function()
    assert.same({ "emph", "ref:x", "strong" }, kinds(with_def("*a*[^x]**b**")))
  end)

  it("keeps an undefined label literal", function()
    local i = para({ "a[^y]", "", "[^x]: Note." })
    assert.same({ "text" }, kinds(i))
    assert.equals("a[^y]", i[1].value)
  end)

  it("keeps an escaped reference literal", function()
    local i = with_def("\\[^x]")
    assert.same({ "text" }, kinds(i))
    assert.equals("[^x]", i[1].value)
  end)

  it("ignores a code span", function()
    assert.same({ "code" }, kinds(with_def("`[^x]`")))
  end)

  it("allows two references and adjacent references", function()
    assert.same({ "ref:x", "text", "ref:x" }, kinds(with_def("[^x] and [^x]")))
    local i = para({ "[^a][^b]", "", "[^a]: A", "[^b]: B" })
    assert.same({ "ref:a", "ref:b" }, kinds(i))
  end)

  it("accepts punctuation and matches labels case-insensitively", function()
    assert.same({ "ref:a-1.b" }, kinds(with_def("[^A-1.B]", "a-1.b")))
    assert.same({ "ref:a" }, kinds(with_def("[^a]", "A")))
  end)

  it("wins over link syntax only when defined", function()
    assert.same({ "ref:x", "text" }, kinds(with_def("[^x](url)")))
    assert.same({ "link" }, kinds(para({ "[^y](url)", "", "[^x]: N" })))
    local i = para({ "[^x][r]", "", "[^x]: N", "", "[r]: /u" })
    assert.same({ "ref:x", "link" }, kinds(i))
  end)

  it("nests inside link text", function()
    local i = with_def("[a [^x]](url)")
    assert.same({ "link" }, kinds(i))
    assert.same({ "text", "ref:x" }, kinds(i[1].inlines))
  end)

  it("is not a reference in an image alt position", function()
    local i = with_def("t ![a [^x]](u.png)")
    assert.same({ "text", "image" }, kinds(i))
    assert.equals("a [^x]", i[2].alt)
  end)

  it("first definition wins for duplicates (one label)", function()
    local doc = block.parse({ "[^x]", "", "[^x]: one", "", "[^x]: two" })
    assert.same({ "ref:x" }, kinds(doc.children[1].inlines))
  end)
end)
