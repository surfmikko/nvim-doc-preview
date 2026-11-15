local box = require("doc_preview.core.box")
local text = require("doc_preview.core.text")

describe("core.box", function()
  it("builds unicode rules for the four positions", function()
    assert.equals("┌───┬─────┐", box.rule({ 1, 3 }, "top"))
    assert.equals("├───┼─────┤", box.rule({ 1, 3 }, "header"))
    assert.equals("├───┼─────┤", box.rule({ 1, 3 }, "row"))
    assert.equals("└───┴─────┘", box.rule({ 1, 3 }, "bottom"))
  end)

  it("builds ascii rules", function()
    assert.equals("+---+-----+", box.rule({ 1, 3 }, "top", "ascii"))
    assert.equals("+---+-----+", box.rule({ 1, 3 }, "bottom", "ascii"))
  end)

  it("handles a single column", function()
    assert.equals("┌────┐", box.rule({ 2 }, "top", "unicode"))
  end)

  it("rule display width is sum(widths) + 3 per column + 1", function()
    assert.equals(13, text.width(box.rule({ 2, 4 }, "top")))
    assert.equals(13, text.width(box.rule({ 2, 4 }, "top", "ascii")))
  end)

  it("exposes vertical glyphs per charset", function()
    assert.equals("│", box.glyphs("unicode").v)
    assert.equals("|", box.glyphs("ascii").v)
    assert.equals("│", box.glyphs().v)
  end)

  it("exposes rule, quote and bullet glyphs per charset", function()
    assert.equals("─", box.rule_glyph())
    assert.equals("-", box.rule_glyph("ascii"))
    assert.equals("│ ", box.quote_prefix("unicode"))
    assert.equals("| ", box.quote_prefix("ascii"))
    assert.equals("•", box.bullet("unicode", 0))
    assert.equals("▪", box.bullet("unicode", 2))
    assert.equals("•", box.bullet("unicode", 3))
    assert.equals("*", box.bullet("ascii", 0))
    assert.equals("-", box.bullet("ascii", 1))
    assert.equals("+", box.bullet("ascii", 2))
  end)

  it("keeps display widths equal across charsets", function()
    for _, k in ipairs({ "rule", "quote" }) do
      assert.equals(text.width(box.glyphs("unicode")[k]), text.width(box.glyphs("ascii")[k]))
    end
    for i = 1, 3 do
      local u, a = box.glyphs("unicode").bullets[i], box.glyphs("ascii").bullets[i]
      assert.equals(text.width(u), text.width(a))
    end
  end)
end)
