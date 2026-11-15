local block = require("doc_preview.markdown.block")
local inline = require("doc_preview.markdown.inline")
local project = require("pairs.project_html")

-- HTML of a whole document (blocks joined by newlines).
local function doc(src)
  return (project.project(block.parse(vim.split(src, "\n", { plain = true }))))
end

-- HTML of one paragraph.
local function html(src)
  return (doc(src):gsub("^<p>", ""):gsub("</p>$", ""))
end

describe("markdown.inline inline links", function()
  it("parses text, destination and title", function()
    assert.equals('<a href="/u">a</a>', html("[a](/u)"))
    assert.equals('<a href="/u" title="t">a</a>', html('[a](/u "t")'))
    assert.equals('<a href="/u" title="t">a</a>', html("[a](/u 't')"))
    assert.equals('<a href="/u" title="t">a</a>', html("[a](/u (t))"))
    assert.equals('<a href="">a</a>', html("[a]()"))
    assert.equals('<a href="/a%20b">a</a>', html("[a](</a b>)"))
  end)

  it("builds a link node", function()
    local nodes = inline.parse("x [a *b*](/u 't')")
    assert.equals("link", nodes[2].kind)
    assert.equals("/u", nodes[2].target)
    assert.equals("t", nodes[2].title)
    assert.equals("emph", nodes[2].inlines[2].kind)
  end)

  it("balances parentheses and resolves escapes in the destination", function()
    assert.equals('<a href="/a(b)">a</a>', html("[a](/a(b))"))
    assert.equals('<a href="/a)">a</a>', html("[a](/a\\))"))
    assert.equals('<a href="/a&amp;b">a</a>', html("[a](/a&amp;b)"))
  end)

  it("keeps emphasis inside the text and out of the destination", function()
    assert.equals('<a href="/u"><em>a</em></a>', html("[*a*](/u)"))
    assert.equals('<em><a href="/u">a</a></em>', html("*[a](/u)*"))
    assert.equals('<a href="/a_b_c">a</a>', html("[a](/a_b_c)"))
  end)

  it("does not let emphasis delimiters cross the link text", function()
    assert.equals('*<a href="/u">a*</a>', html("*[a*](/u)"))
  end)

  it("does not nest links but nests images in links", function()
    assert.equals('[a <a href="/u">b</a> c](/v)', html("[a [b](/u) c](/v)"))
    assert.equals('<a href="/c"><img src="/b" alt="a" /></a>', html("[![a](/b)](/c)"))
  end)

  it("takes code spans over brackets", function()
    assert.equals("[<code>a](/u)</code>", html("[`a](/u)`"))
    assert.equals('<a href="/u"><code>a</code></a>', html("[`a`](/u)"))
  end)

  it("leaves malformed links literal", function()
    assert.equals("[a](/u", html("[a](/u"))
    assert.equals("[a] (/u)", html("[a] (/u)"))
    assert.equals("[a](/u 'x' y)", html("[a](/u 'x' y)"))
    assert.equals("a]", html("a]"))
    assert.equals("[a", html("[a"))
  end)

  it("allows a line ending inside the parentheses", function()
    assert.equals('<a href="/u" title="t">a</a>', html('[a](/u\n"t")'))
  end)
end)

describe("markdown.inline images", function()
  it("parses alt text, destination and title", function()
    assert.equals('<img src="/i" alt="a" />', html("![a](/i)"))
    assert.equals('<img src="/i" alt="a" title="t" />', html('![a](/i "t")'))
    assert.equals('<img src="/i" alt="" />', html("![](/i)"))
  end)

  it("uses the plain text of the description as alt", function()
    assert.equals('<img src="/i" alt="a b c" />', html("![a *b* `c`](/i)"))
    assert.equals('<img src="/i" alt="a b" />', html("![a [b](/x)](/i)"))
  end)

  it("keeps a lone exclamation mark literal", function()
    assert.equals("a! [b](c", html("a! [b](c"))
  end)

  it("builds an image node with plain alt", function()
    local n = inline.parse("![a *b*](/i)")[1]
    assert.equals("image", n.kind)
    assert.equals("a b", n.alt)
    assert.equals("/i", n.target)
  end)
end)

describe("markdown.inline autolinks", function()
  it("links URIs and emails, showing the text as written", function()
    assert.equals(
      '<a href="http://a.b/c?x=1&amp;y=2">http://a.b/c?x=1&amp;y=2</a>',
      html("<http://a.b/c?x=1&y=2>")
    )
    assert.equals('<a href="mailto:a@b.co">a@b.co</a>', html("<a@b.co>"))
  end)

  it("does not process markup or escapes inside", function()
    assert.equals('<a href="http://a/*b*">http://a/*b*</a>', html("<http://a/*b*>"))
  end)

  it("leaves non-autolinks literal", function()
    assert.equals("&lt;http://a b&gt;", html("<http://a b>"))
    assert.equals("&lt;a:b&gt;", html("<a:b>"))
    assert.equals("a &lt; b", html("a < b"))
  end)

  it("builds a link node whose text is the target", function()
    local n = inline.parse("<http://a.b>")[1]
    assert.equals("link", n.kind)
    assert.equals("http://a.b", n.target)
    assert.equals("http://a.b", n.inlines[1].value)
  end)
end)

describe("markdown.inline reference links", function()
  local refs = { foo = { target = "/f", title = "T" }, ["a b"] = { target = "/ab" } }

  it("resolves full, collapsed and shortcut references", function()
    local function h(s)
      local n = inline.parse(s, refs)
      return project.project({ children = { { kind = "paragraph", inlines = n } } })
    end
    assert.equals('<p><a href="/f" title="T">x</a></p>', h("[x][foo]"))
    assert.equals('<p><a href="/f" title="T">foo</a></p>', h("[foo][]"))
    assert.equals('<p><a href="/f" title="T">foo</a></p>', h("[foo]"))
    assert.equals('<p><img src="/f" alt="foo" title="T" /></p>', h("![foo]"))
    assert.equals('<p><img src="/f" alt="x" title="T" /></p>', h("![x][foo]"))
  end)

  it("matches labels case-insensitively with collapsed whitespace", function()
    local n = inline.parse("[FOO] [a   B]", refs)
    assert.equals("/f", n[1].target)
    assert.equals("/ab", n[3].target)
  end)

  it("leaves undefined references literal", function()
    local n = inline.parse("[nope] [x][nope] ![nope]", refs)
    assert.equals(1, #n)
    assert.equals("[nope] [x][nope] ![nope]", n[1].value)
  end)

  it("does not fall back to the shortcut when a full label is undefined", function()
    local n = inline.parse("[foo][nope]", refs)
    assert.equals(1, #n)
    assert.equals("[foo][nope]", n[1].value)
  end)

  it("prefers an inline tail, falls back to a shortcut when it is malformed", function()
    assert.equals("/u", inline.parse("[foo](/u)", refs)[1].target)
    local n = inline.parse("[foo](bad title", refs)
    assert.equals("/f", n[1].target)
    assert.equals("(bad title", n[2].value)
  end)

  it("needs bracket-free link text for collapsed and shortcut forms", function()
    local n = inline.parse("[[foo]]", refs)
    assert.equals("[", n[1].value)
    assert.equals("link", n[2].kind)
    assert.equals("]", n[3].value)
  end)

  it("treats links inside reference link text as nested links", function()
    assert.equals("[a ", inline.parse("[a [foo]][foo]", refs)[1].value)
  end)
end)

describe("markdown.block link reference definitions", function()
  it("resolves definitions that come after the use", function()
    assert.equals('<p><a href="/u">a</a></p>', doc("[a]\n\n[a]: /u"))
  end)

  it("removes the definition lines and moves the source range", function()
    local d = block.parse({ "[a]: /u", "[b]: /v", "text [a]" })
    assert.equals(1, #d.children)
    assert.equals(3, d.children[1].src_start)
    assert.equals(3, d.children[1].src_end)
  end)

  it("drops paragraphs that held only definitions", function()
    assert.equals("", doc("[a]: /u\n\n[b]: /v"))
    assert.equals("<p>x</p>", doc("[a]: /u\n\nx"))
  end)

  it("keeps the first definition of a label", function()
    assert.equals('<p><a href="/1">a</a></p>', doc("[a]: /1\n\n[A]: /2\n\n[a]"))
  end)

  it("takes titles on the same or the next line", function()
    assert.equals('<p><a href="/u" title="t">a</a></p>', doc("[a]: /u 't'\n\n[a]"))
    assert.equals('<p><a href="/u" title="t">a</a></p>', doc('[a]: /u\n"t"\n\n[a]'))
  end)

  it("only reads definitions at the start of a paragraph", function()
    assert.equals("<p>x\n[a]: /u</p>", doc("x\n[a]: /u"))
    assert.equals("<p>[a]: /u &quot;t&quot; x</p>", doc('[a]: /u "t" x'))
  end)

  it("keeps text after the definitions as the paragraph", function()
    assert.equals('<p><a href="/u">a</a>\nmore</p>', doc("[a]: /u\n[a]\nmore"))
  end)

  it("resolves references in headings", function()
    assert.equals('<h1><a href="/u">a</a></h1>\n', doc("# [a]\n\n[a]: /u") .. "\n")
  end)
end)
