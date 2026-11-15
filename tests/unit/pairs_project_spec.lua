local model = require("doc_preview.document.model")
local block = require("doc_preview.markdown.block")
local html = require("pairs.project_html")

local function proj(lines)
  return (html.project(block.parse(lines)))
end

describe("pairs.project_html", function()
  it("projects headings and paragraphs from hand-built trees", function()
    local doc = model.document({
      model.heading(3, { model.text("t") }, 1, 1),
      model.paragraph({ model.text("p") }, 2, 2),
    }, 1, 2)
    assert.equals("<h3>t</h3>\n<p>p</p>", (html.project(doc)))
  end)

  it("projects parsed input", function()
    assert.equals("<h1>a</h1>", proj({ "# a" }))
    assert.equals("<h1>a</h1>", proj({ "a", "=" }))
    assert.equals("<p>a\nb</p>", proj({ "a", "  b" }))
    assert.equals("<h1></h1>", proj({ "#" }))
  end)

  it("projects links and images with cmark-style escaping", function()
    local doc = model.document({
      model.paragraph({
        model.link("/a b&c'", 'x"y', { model.text("t") }),
        model.link("", nil, {}),
        model.image("/i\\", nil, "a<b"),
        model.image("/i", "T", "alt"),
      }, 1, 1),
    }, 1, 1)
    assert.equals(
      '<p><a href="/a%20b&amp;c&#x27;" title="x&quot;y">t</a><a href=""></a>'
        .. '<img src="/i%5C" alt="a&lt;b" /><img src="/i" alt="alt" title="T" /></p>',
      (html.project(doc))
    )
  end)

  it("projects a block image as a paragraph with an img", function()
    local doc = model.document({ model.image_block("/i", "T", "a<b", 1, 1) }, 1, 1)
    assert.equals('<p><img src="/i" alt="a&lt;b" title="T" /></p>', (html.project(doc)))
    assert.equals('<p><img src="/i" alt="a" /></p>', proj({ "![a](/i)" }))
    assert.equals('<ul>\n<li><img src="/i" alt="a" /></li>\n</ul>', proj({ "- ![a](/i)" }))
  end)

  it("projects thematic breaks", function()
    local doc = model.document({
      model.paragraph({ model.text("a") }, 1, 1),
      model.thematic_break(2, 2),
    }, 1, 2)
    assert.equals("<p>a</p>\n<hr />", (html.project(doc)))
    assert.equals("<hr />", proj({ "***" }))
    assert.equals("<p>a</p>\n<hr />\n<p>b</p>", proj({ "a", "", "---", "", "b" }))
    assert.equals("<h2>Foo</h2>", proj({ "Foo", "---" }))
  end)

  it("escapes text", function()
    assert.equals("<p>&amp; &lt;1&gt; &quot;</p>", proj({ '& <1> "' }))
  end)

  it("marks unknown kinds as unsupported without raising", function()
    local doc = model.document({ { kind = "md:thing", src_start = 1, src_end = 1 } }, 1, 1)
    local out, unsupported = html.project(doc)
    assert.equals("<!--unsupported:md:thing-->", out)
    assert.same({ "md:thing" }, unsupported)
  end)

  it("normalizes line endings, blank lines and the final newline", function()
    assert.equals("<p>a</p>\n<p>b</p>", html.normalize("<p>a</p>  \r\n\n\n<p>b</p>\n"))
  end)
end)

describe("pairs.project_html inlines", function()
  it("projects styled inlines and breaks", function()
    local doc = model.document({
      model.paragraph({
        model.emph({ model.text("a") }),
        model.strong({ model.text("b") }),
        model.strike({ model.text("c") }),
        model.code("<"),
        model.softbreak(),
        model.hardbreak(),
      }, 1, 1),
    }, 1, 1)
    assert.equals(
      "<p><em>a</em><strong>b</strong><del>c</del><code>&lt;</code>\n<br />\n</p>",
      html.project(doc)
    )
  end)
end)

describe("pairs.project_html blockquote", function()
  it("projects a hand-built quote and an empty quote", function()
    local doc = model.document({
      model.blockquote({ model.paragraph({ model.text("a") }, 1, 1) }, 1, 1),
      model.blockquote({}, 3, 3),
    }, 1, 3)
    assert.equals(
      "<blockquote>\n<p>a</p>\n</blockquote>\n<blockquote>\n</blockquote>",
      (html.project(doc))
    )
  end)

  it("projects parsed quotes", function()
    local q = "<blockquote>\n<p>a</p>\n</blockquote>"
    assert.equals(q, proj({ "> a" }))
    assert.equals("<blockquote>\n<p>a\nb</p>\n</blockquote>", proj({ "> a", "b" }))
    assert.equals("<blockquote>\n" .. q .. "\n</blockquote>", proj({ "> > a" }))
    assert.equals(q .. "\n<p>b</p>", proj({ "> a", "", "b" }))
    assert.equals("<blockquote>\n<h1>h</h1>\n</blockquote>", proj({ "> # h" }))
  end)

  it("normalizes nested output", function()
    local out = proj({ "> > a", "", "> b" })
    assert.equals(out, html.normalize(out))
  end)

  it("projects lists in cmark layout", function()
    assert.equals("<ul>\n<li>a</li>\n<li>b</li>\n</ul>", proj({ "- a", "- b" }))
    assert.equals('<ol start="7">\n<li>a</li>\n</ol>', proj({ "7. a" }))
    assert.equals("<ol>\n<li>a</li>\n</ol>", proj({ "1) a" }))
    assert.equals("<ul>\n<li></li>\n</ul>", proj({ "-" }))
    assert.equals(
      "<ul>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n</ul>",
      proj({ "- a", "", "- b" })
    )
    assert.equals("<ul>\n<li>a\n<ul>\n<li>b</li>\n</ul>\n</li>\n</ul>", proj({ "- a", "  - b" }))
    assert.equals(
      "<ul>\n<li>\n<blockquote>\n<p>a</p>\n</blockquote>\n</li>\n</ul>",
      proj({ "- > a" })
    )
  end)

  it("projects task items per cmark-gfm tasklist", function()
    assert.equals(
      '<ul>\n<li><input type="checkbox" disabled="" /> a</li>\n'
        .. '<li><input type="checkbox" checked="" disabled="" /> b</li>\n</ul>',
      proj({ "- [ ] a", "- [x] b" })
    )
  end)
end)

describe("pairs.project_html code_block", function()
  local function code(lang, lines)
    return model.code_block(lang, lines, 1, 1, 1 + #lines)
  end
  local function p(...)
    return (html.project(model.document({ ... })))
  end

  it("projects lang, no lang, escapes and empty", function()
    assert.equals(
      '<pre><code class="language-lua">a\n\nb\n</code></pre>',
      p(code("lua", { "a", "", "b" }))
    )
    assert.equals("<pre><code>a\n</code></pre>", p(code(nil, { "a" })))
    assert.equals("<pre><code>a\n</code></pre>", p(code("", { "a" })))
    assert.equals(
      "<pre><code>&lt;a href=&quot;x&quot;&gt; &amp;\n</code></pre>",
      p(code(nil, { '<a href="x"> &' }))
    )
    assert.equals("<pre><code></code></pre>", p(code(nil, {})))
  end)

  it("projects code in a quote and in tight and loose items", function()
    local c = "<pre><code>a\n</code></pre>"
    assert.equals(
      "<blockquote>\n" .. c .. "\n</blockquote>",
      p(model.blockquote({ code(nil, { "a" }) }, 1, 2))
    )
    local function list(tight)
      local item = model.list_item(nil, { code(nil, { "a" }) }, 1, 2)
      return p(model.list(false, 1, tight, { item }, 1, 2))
    end
    assert.equals("<ul>\n<li>\n" .. c .. "\n</li>\n</ul>", list(true))
    assert.equals("<ul>\n<li>\n" .. c .. "\n</li>\n</ul>", list(false))
  end)
end)

describe("pairs.project_html raw html", function()
  local function p(...)
    return (html.project(model.document({ ... })))
  end
  local function raw(lines)
    return model.html_block(lines, 1, 1, #lines)
  end

  it("projects a block verbatim with no escaping", function()
    assert.equals("<div>\n  a & <b>\n</div>\n", p(raw({ "<div>", "  a & <b>", "</div>" })))
    assert.equals("\n", p(raw({ "" })))
  end)

  it("projects a block in a quote and in tight and loose items", function()
    local b = "<div>\n"
    assert.equals(
      "<blockquote>\n" .. b .. "\n</blockquote>",
      p(model.blockquote({ raw({ "<div>" }) }, 1, 1))
    )
    local function list(tight)
      local item = model.list_item(nil, { raw({ "<div>" }) }, 1, 1)
      return p(model.list(false, 1, tight, { item }, 1, 1))
    end
    assert.equals("<ul>\n<li>\n" .. b .. "\n</li>\n</ul>", list(true))
    assert.equals("<ul>\n<li>\n" .. b .. "\n</li>\n</ul>", list(false))
  end)

  it("projects inline html verbatim in paragraphs, headings and emphasis", function()
    local function h(...)
      return model.html_inline(...)
    end
    assert.equals(
      '<p>a <b class="x"> &amp; <!-- c --></p>',
      p(
        model.paragraph(
          { model.text("a "), h('<b class="x">'), model.text(" & "), h("<!-- c -->") },
          1,
          1
        )
      )
    )
    assert.equals(
      "<h2><i>x</i></h2>",
      p(model.heading(2, { h("<i>"), model.text("x"), h("</i>") }, 1, 1))
    )
    assert.equals(
      "<p><em>a<br>&lt;</em></p>",
      p(model.paragraph({ model.emph({ model.text("a"), h("<br>"), model.text("<") }) }, 1, 1))
    )
  end)

  describe("tables", function()
    local function c(...)
      return { inlines = { ... } }
    end
    local function t(...)
      return p(model.table(...))
    end

    it("projects alignments and body rows", function()
      assert.equals(
        table.concat({
          "<table>",
          "<thead>",
          "<tr>",
          '<th align="left">a</th>',
          '<th align="center">b</th>',
          '<th align="right">c</th>',
          "<th>d</th>",
          "</tr>",
          "</thead>",
          "<tbody>",
          "<tr>",
          '<td align="left">1</td>',
          '<td align="center">2</td>',
          '<td align="right">3</td>',
          "<td></td>",
          "</tr>",
          "</tbody>",
          "</table>",
        }, "\n"),
        t(
          { "left", "center", "right", nil },
          { c(model.text("a")), c(model.text("b")), c(model.text("c")), c(model.text("d")) },
          { { c(model.text("1")), c(model.text("2")), c(model.text("3")), c() } },
          1,
          3
        )
      )
    end)

    it("omits tbody when there are no body rows", function()
      assert.equals(
        "<table>\n<thead>\n<tr>\n<th>a</th>\n</tr>\n</thead>\n</table>",
        t({}, { c(model.text("a")) }, {}, 1, 2)
      )
    end)

    it("escapes content and projects inline markup in cells", function()
      assert.equals(
        "<table>\n<thead>\n<tr>\n<th>a&lt;|&amp;</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n"
          .. '<td><em>x</em><code>&lt;</code><a href="/u">l</a></td>\n</tr>\n</tbody>\n</table>',
        t({}, { c(model.text("a<|&")) }, {
          {
            c(
              model.emph({ model.text("x") }),
              model.code("<"),
              model.link("/u", nil, { model.text("l") })
            ),
          },
        }, 1, 3)
      )
    end)

    it("projects a table inside a quote", function()
      local tbl = model.table({}, { c(model.text("a")) }, {}, 1, 2)
      assert.equals(
        "<blockquote>\n<table>\n<thead>\n<tr>\n<th>a</th>\n</tr>\n</thead>\n</table>\n</blockquote>",
        p(model.blockquote({ tbl }, 1, 2))
      )
    end)
  end)
end)

describe("pairs.project_html footnotes", function()
  local function ref(label)
    return model.footnote_ref(label)
  end
  local function def(label, kids)
    return model.footnote_def(label, kids, 1, 1)
  end
  local function para(...)
    return model.paragraph({ ... }, 1, 1)
  end
  local function sup(label, n, id)
    return string.format(
      '<sup class="footnote-ref"><a href="#fn-%s" id="fnref-%s" data-footnote-ref>%d</a></sup>',
      label,
      id or label,
      n
    )
  end
  local function back(label, idx, id, sup_n)
    return string.format(
      ' <a href="#fnref-%s" class="footnote-backref" data-footnote-backref'
        .. ' data-footnote-backref-idx="%s" aria-label="Back to reference %s">\u{21A9}%s</a>',
      id or label,
      idx,
      idx,
      sup_n and ('<sup class="footnote-ref">' .. sup_n .. "</sup>") or ""
    )
  end
  local function section(entries)
    return '<section class="footnotes" data-footnotes>\n<ol>\n' .. entries .. "\n</ol>\n</section>"
  end

  it("projects a single reference and its section", function()
    local doc = model.document({
      para(model.text("a"), ref("x")),
      def("x", { para(model.text("note")) }),
    }, 1, 2)
    assert.equals(
      "<p>a"
        .. sup("x", 1)
        .. "</p>\n"
        .. section('<li id="fn-x">\n<p>note' .. back("x", "1") .. "</p>\n</li>"),
      (html.project(doc))
    )
  end)

  it("numbers by first use and adds a back-reference per repeated use", function()
    local doc = model.document({
      def("a", { para(model.text("A")) }),
      def("b", { para(model.text("B")) }),
      para(ref("b"), ref("a"), ref("b")),
    }, 1, 3)
    local out = html.project(doc)
    assert.equals(
      "<p>"
        .. sup("b", 1)
        .. sup("a", 2)
        .. sup("b", 1, "b-2")
        .. "</p>\n"
        .. section(
          '<li id="fn-b">\n<p>B'
            .. back("b", "1")
            .. back("b", "1-2", "b-2", 2)
            .. '</p>\n</li>\n<li id="fn-a">\n<p>A'
            .. back("a", "2")
            .. "</p>\n</li>"
        ),
      out
    )
  end)

  it("omits unused definitions and keeps undefined references literal", function()
    local doc = model.document({
      def("u", { para(model.text("U")) }),
      para(ref("none")),
    }, 1, 2)
    assert.equals("<p>[^none]</p>", (html.project(doc)))
  end)

  it("projects a multi-paragraph body with the back-reference in the last paragraph", function()
    local doc = model.document({
      para(ref("x")),
      def("x", { para(model.text("one")), para(model.text("two")) }),
    }, 1, 2)
    assert.equals(
      "<p>"
        .. sup("x", 1)
        .. "</p>\n"
        .. section('<li id="fn-x">\n<p>one</p>\n<p>two' .. back("x", "1") .. "</p>\n</li>"),
      (html.project(doc))
    )
  end)

  it("puts the back-reference bare after a non-paragraph body", function()
    local doc = model.document({
      para(ref("x")),
      def("x", { model.code_block("", { "c" }, 1, 1) }),
    }, 1, 2)
    local out = html.project(doc)
    assert.truthy(out:find('<pre><code>c\n</code></pre>\n<a href="#fnref-x"', 1, true))
  end)

  it("projects a reference in a table cell", function()
    local doc = model.document({
      model.table({}, { { inlines = { ref("x") } } }, {}, 1, 1),
      def("x", { para(model.text("n")) }),
    }, 1, 2)
    local out = html.project(doc)
    assert.truthy(out:find("<th>" .. sup("x", 1, nil) .. "</th>", 1, true))
    assert.truthy(out:find('<li id="fn-x">', 1, true))
  end)

  it("numbers a reference inside a footnote body after the earlier ones", function()
    local doc = model.document({
      para(ref("a")),
      def("a", { para(model.text("A"), ref("b")) }),
      def("b", { para(model.text("B")) }),
    }, 1, 3)
    local out = html.project(doc)
    assert.truthy(out:find(sup("b", 2), 1, true))
    assert.truthy(out:find('<li id="fn-b">\n<p>B' .. back("b", "2"), 1, true))
  end)

  it("projects parsed input", function()
    local out = proj({ "a[^1]", "", "[^1]: n" })
    assert.equals(
      "<p>a"
        .. sup("1", 1)
        .. "</p>\n"
        .. section('<li id="fn-1">\n<p>n' .. back("1", "1") .. "</p>\n</li>"),
      out
    )
  end)
end)
