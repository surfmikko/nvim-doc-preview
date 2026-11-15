local inline = require("doc_preview.markdown.inline")
local project = require("pairs.project_html")

-- HTML of one paragraph, through the same projection the pairs use.
local function html(src)
  local block = require("doc_preview.markdown.block")
  local out = project.project(block.parse(vim.split(src, "\n", { plain = true })))
  return (out:gsub("^<p>", ""):gsub("</p>$", ""))
end

describe("markdown.inline", function()
  it("parses plain text to one text node", function()
    assert.same({ { kind = "text", value = "a b" } }, inline.parse("a b"))
    assert.same({}, inline.parse(""))
  end)

  describe("code spans", function()
    it("matches backtick runs of equal length", function()
      assert.equals("<code>a</code>", html("`a`"))
      assert.equals("<code>a`b</code>", html("``a`b``"))
      assert.equals("`a", html("`a"))
      assert.equals("``a`", html("``a`"))
    end)

    it("strips one surrounding space and turns newlines into spaces", function()
      assert.equals("<code>a</code>", html("` a `"))
      assert.equals("<code>  </code>", html("`  `"))
      assert.equals("<code>a b</code>", html("`a\nb`"))
    end)

    it("takes precedence over emphasis and escapes", function()
      assert.equals("*<code>a*</code>", html("*`a*`"))
      assert.equals("<code>\\*</code>", html("`\\*`"))
      assert.equals("`a`", html("\\`a`"))
    end)
  end)

  describe("emphasis", function()
    it("handles emphasis and strong", function()
      assert.equals("<em>a</em>", html("*a*"))
      assert.equals("<strong>a</strong>", html("**a**"))
      assert.equals("<em>a</em> <strong>b</strong>", html("_a_ __b__"))
      assert.equals("<em><strong>a</strong></em>", html("***a***"))
    end)

    it("needs flanking delimiters", function()
      assert.equals("a * b *", html("a * b *"))
      assert.equals("<em>a</em>b", html("*a*b"))
      assert.equals("a_b_c", html("a_b_c"))
      assert.equals("a<em>b</em>c", html("a*b*c"))
      assert.equals("**", html("**"))
    end)

    it("nests and splits runs", function()
      assert.equals("<strong>a <em>b</em></strong>", html("**a *b***"))
      assert.equals("*<em>a</em>", html("**a*"))
      assert.equals("<em>a</em>*", html("*a**"))
      assert.equals("<em>a <strong>b</strong> c</em>", html("*a **b** c*"))
    end)

    it("applies the multiple-of-three rule", function()
      assert.equals("<em>a<strong>b</strong>c</em>", html("*a**b**c*"))
      assert.equals("<em>a**b</em>", html("*a**b*"))
    end)

    it("keeps unmatched delimiters as text", function()
      assert.equals("*a", html("*a"))
      assert.equals("a**", html("a**"))
    end)

    it("works across a soft break", function()
      assert.equals("<em>a\nb</em>", html("*a\nb*"))
    end)
  end)

  describe("strikethrough", function()
    it("handles one or two tildes of equal length", function()
      assert.equals("<del>a</del>", html("~~a~~"))
      assert.equals("<del>a</del>", html("~a~"))
      assert.equals("~~a~", html("~~a~"))
      assert.equals("x ~~~a~~~", html("x ~~~a~~~"))
      assert.equals("a ~~ b ~~", html("a ~~ b ~~"))
      assert.equals("~~a~ and ~a~~", html("~~a~ and ~a~~"))
    end)

    it("nests with emphasis", function()
      assert.equals("<del><em>a</em></del>", html("~~*a*~~"))
    end)
  end)

  describe("backslash escapes", function()
    it("escapes ASCII punctuation only", function()
      assert.equals("*a*", html("\\*a\\*"))
      assert.equals("\\a", html("\\a"))
      assert.equals("a\\", html("a\\"))
      assert.equals("\\", html("\\\\"))
    end)
  end)

  describe("entities", function()
    it("decodes named and numeric references", function()
      assert.equals("&amp; &lt; &quot;", html("&amp; &lt; &quot;"))
      assert.equals("A A", html("&#65; &#x41;"))
      assert.equals("©", html("&copy;"))
      assert.equals("\239\191\189", html("&#0;"))
      assert.equals("\240\159\152\128", html("&#x1F600;"))
    end)

    it("keeps invalid references literal", function()
      assert.equals("&amp;nosuch;", html("&nosuch;"))
      assert.equals("&amp;#12345678;", html("&#12345678;"))
      assert.equals("&amp; x", html("& x"))
    end)

    it("does not turn decoded characters into markup", function()
      assert.equals("*a*", html("&#42;a&#42;"))
      assert.equals("&lt;b&gt;", html("&lt;b&gt;"))
    end)
  end)

  describe("breaks", function()
    it("makes a hard break from two spaces or a backslash", function()
      assert.equals("a<br />\nb", html("a  \nb"))
      assert.equals("a<br />\nb", html("a\\\nb"))
      assert.equals("a<br />\nb", html("a     \nb"))
    end)

    it("makes a soft break from one space or none", function()
      assert.equals("a\nb", html("a \nb"))
      assert.equals("a\nb", html("a\nb"))
    end)

    it("drops trailing spaces at the end and leading spaces of continuations", function()
      assert.equals("a", html("a  "))
      assert.equals("a\nb", html("a\n   b"))
    end)

    it("does not break inside code spans", function()
      assert.equals("<code>a   b</code>", html("`a  \nb`"))
    end)
  end)

  describe("raw html", function()
    local function kinds(src)
      local out = {}
      for _, n in ipairs(inline.parse(src)) do
        out[#out + 1] = n.kind
      end
      return out
    end

    it("makes one atomic node per tag", function()
      assert.same({ { kind = "html_inline", value = "<b>" } }, inline.parse("<b>"))
      assert.same({ "text", "html_inline", "text" }, kinds("a <!-- c --> b"))
      assert.same({ "html_inline" }, kinds('<a\nhref="x">'))
    end)

    it("leaves invalid forms as text", function()
      assert.same({ { kind = "text", value = "<a" } }, inline.parse("<a"))
      assert.equals("&lt;1&gt;", html("<1>"))
    end)

    it("lets autolinks win", function()
      assert.same({ "link" }, kinds("<http://x>"))
      assert.same({ "link" }, kinds("<a@b.co>"))
    end)

    it("works inside emphasis and link text", function()
      assert.equals("<em>a <b> c</em>", html("*a <b> c*"))
      assert.equals('<a href="u">x <i> y</a>', html("[x <i> y](u)"))
    end)

    it("does not match delimiters across the node", function()
      assert.equals("<em><b></em>", html("*<b>*"))
      assert.equals('<em>a <b c="*"> d</em>', html('*a <b c="*"> d*'))
    end)

    it("keeps code spans, entities and escapes", function()
      assert.equals("<code>&lt;b&gt;</code>", html("`<b>`"))
      assert.equals('x <a href="&amp;">', html('x <a href="&amp;">'))
      assert.equals("&lt;b&gt;", html("\\<b>"))
    end)
  end)
end)
