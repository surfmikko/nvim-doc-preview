local model = require("doc_preview.document.model")
local block = require("doc_preview.markdown.block")
local gfm_table = require("doc_preview.markdown.table")

local function plain(inlines)
  local parts = {}
  for _, n in ipairs(inlines) do
    parts[#parts + 1] = n.value or plain(n.inlines)
  end
  return table.concat(parts)
end

local function texts(row)
  local out = {}
  for i, cell in ipairs(row) do
    out[i] = plain(cell.inlines)
  end
  return out
end

local function parse(lines)
  local doc = block.parse(lines)
  assert.is_true(model.validate(doc))
  return doc.children
end

describe("markdown.table split_row and delimiter", function()
  it("splits with and without outer pipes, trimming", function()
    assert.same({ "a", "b" }, gfm_table.split_row("| a | b |"))
    assert.same({ "a", "b" }, gfm_table.split_row("a|b"))
    assert.same({ "a", "" }, gfm_table.split_row("a| |"))
    assert.same({ "a" }, gfm_table.split_row("a|"))
  end)

  it("keeps escaped pipes as pipes", function()
    assert.same({ "a|b", "c" }, gfm_table.split_row("a\\|b|c"))
  end)

  it("recognises delimiter rows and alignment", function()
    assert.same({ "left", "center", "right" }, gfm_table.delimiter("|:--|:-:|--:|"))
    local a, n = gfm_table.delimiter("--- | :-")
    assert.equals("left", a[2])
    assert.equals(2, n)
    assert.equals(1, select(2, gfm_table.delimiter("| --- |")))
  end)

  it("rejects non-delimiters", function()
    assert.is_nil(gfm_table.delimiter("---"))
    assert.is_nil(gfm_table.delimiter("|"))
    assert.is_nil(gfm_table.delimiter("| a | b |"))
    assert.is_nil(gfm_table.delimiter("    | - | - |"))
    assert.is_nil(gfm_table.delimiter("| : | - |"))
  end)
end)

describe("markdown.block tables", function()
  it("parses a basic table with ranges at line > 1", function()
    local c = parse({ "", "", "| a | b |", "|---|---|", "| 1 | 2 |", "| 3 | 4 |" })
    assert.equals(1, #c)
    assert.equals("table", c[1].kind)
    assert.equals(3, c[1].src_start)
    assert.equals(6, c[1].src_end)
    assert.same({ "a", "b" }, texts(c[1].header))
    assert.same({ "3", "4" }, texts(c[1].rows[2]))
  end)

  it("works without outer pipes and with alignments", function()
    local c = parse({ "a | b | c", ":-- | :-: | --:", "1 | 2 | 3" })
    assert.same({ "left", "center", "right" }, c[1].align)
    assert.equals(1, #c[1].rows)
  end)

  it("needs equal header and delimiter cell counts", function()
    local c = parse({ "| a | b |", "|---|" })
    assert.equals(1, #c)
    assert.equals("paragraph", c[1].kind)
  end)

  it("keeps setext and thematic meaning of pipeless delimiters", function()
    local c = parse({ "a", "---" })
    assert.equals("heading", c[1].kind)
    c = parse({ "| a |", "- - -" })
    assert.equals("paragraph", c[1].kind)
    c = parse({ "a", "| --- |" })
    assert.equals("table", c[1].kind)
  end)

  it("pads short rows and drops extra cells", function()
    local c = parse({ "a|b", "-|-", "1", "1|2|3" })
    assert.same({ "1", "" }, texts(c[1].rows[1]))
    assert.same({ "1", "2" }, texts(c[1].rows[2]))
  end)

  it("handles escaped pipes and pipes in code spans", function()
    local c = parse({ "a|b", "-|-", "x\\|y|z", "`p|q`|w" })
    assert.same({ "x|y", "z" }, texts(c[1].rows[1]))
    assert.same({ "`p", "q`" }, { plain(c[1].rows[2][1].inlines), plain(c[1].rows[2][2].inlines) })
  end)

  it("parses inline markup and reference links in cells", function()
    local c = parse({ "| *a* | [x][r] |", "|---|---|", "| `c` | |", "", "[r]: http://e.com" })
    assert.equals("emph", c[1].header[1].inlines[1].kind)
    assert.equals("link", c[1].header[2].inlines[1].kind)
    assert.same({ "c", "" }, texts(c[1].rows[1]))
  end)

  it("interrupts a paragraph; earlier lines stay a paragraph", function()
    local c = parse({ "intro", "more", "a|b", "-|-", "1|2" })
    assert.equals(2, #c)
    assert.equals("paragraph", c[1].kind)
    assert.equals(2, c[1].src_end)
    assert.equals(3, c[2].src_start)
  end)

  it("supports a header-only table", function()
    local c = parse({ "a|b", "-|-" })
    assert.equals(0, #c[1].rows)
    assert.equals(2, c[1].src_end)
  end)

  it("ends at a blank line, then a paragraph follows", function()
    local c = parse({ "a|b", "-|-", "1|2", "", "after" })
    assert.equals(3, c[1].src_end)
    assert.equals("paragraph", c[2].kind)
    assert.equals(5, c[2].src_start)
  end)

  it("ends at other block starts", function()
    local cases = {
      { "# h", "heading" },
      { "> q", "blockquote" },
      { "```", "code_block" },
      { "- i", "list" },
      { "***", "thematic_break" },
    }
    for _, case in ipairs(cases) do
      local c = parse({ "a|b", "-|-", "1|2", case[1], "x" })
      assert.equals("table", c[1].kind)
      assert.equals(3, c[1].src_end)
      assert.equals(case[2], c[2].kind)
    end
  end)

  it("a text line right after the last row is another row", function()
    local c = parse({ "a|b", "-|-", "1|2", "text" })
    assert.equals(2, #c[1].rows)
  end)
end)

describe("markdown.table list-start delimiter rows", function()
  local function kinds(lines)
    local out = {}
    for i, n in ipairs(parse(lines)) do
      out[i] = n.kind
    end
    return out
  end

  it("lets a bullet start win over the delimiter row", function()
    assert.same({ "paragraph", "list" }, kinds({ "a | b", "- | -", "1 | 2" }))
    assert.same({ "paragraph", "list" }, kinds({ "a | b |", "- | - |", "1 | 2 |" }))
  end)

  it("still builds tables for -|-, | - | and :- rows", function()
    assert.same({ "table" }, kinds({ "a|b", "-|-", "1|2" }))
    assert.same({ "table" }, kinds({ "| a |", "| - |", "| 1 |" }))
    assert.same({ "table" }, kinds({ "| a |", ":-|", "| 1 |" }))
  end)
end)
