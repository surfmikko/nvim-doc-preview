local block = require("doc_preview.markdown.block")
local render = require("doc_preview.document.render")

local function out(src, width)
  return render.render(block.parse(vim.split(src, "\n", { plain = true })), { width = width or 40 })
end

local function find(o, group)
  local res = {}
  for _, s in ipairs(o.spans) do
    if s.hl_group == group then
      res[#res + 1] = { s.line, s.col_start, s.col_end }
    end
  end
  return res
end

describe("document.render links", function()
  it("renders text plus a marker and a Links section", function()
    local o = out("see [the docs](http://x.y/d) now")
    assert.same({ "see the docs[1] now", "", "Links", "[1] http://x.y/d" }, o.lines)
    assert.same({ { 1, 4, 12 } }, find(o, "DocPreviewLink"))
    assert.same({ { 1, 12, 15 }, { 4, 0, 3 } }, find(o, "DocPreviewLinkMark"))
    assert.same({ { 3, 0, 5 } }, find(o, "DocPreviewH2"))
  end)

  it("numbers in order of first use and lets duplicates share a number", function()
    local o = out("[a](/1) [b](/2) [c](/1)\n\n[d](/2) [e](/3)")
    assert.same({
      "a[1] b[2] c[1]",
      "",
      "d[2] e[3]",
      "",
      "Links",
      "[1] /1",
      "[2] /2",
      "[3] /3",
    }, o.lines)
  end)

  it("ignores the title for numbering and omits it from the list", function()
    local o = out('[a](/1 "t") [b](/1)')
    assert.same({ "a[1] b[1]", "", "Links", "[1] /1" }, o.lines)
  end)

  it("numbers links in headings and shows autolinks and images", function()
    local o = out("# [h](/h)\n\n<http://a.b> ![alt](/i)")
    assert.same(
      { "h[1]", "", "http://a.b[2] [image: alt]", "", "Links", "[1] /h", "[2] http://a.b" },
      o.lines
    )
  end)

  it("adds no section without links and restarts numbering per render", function()
    assert.same({ "plain" }, out("plain").lines)
    assert.same({ "a[1]", "", "Links", "[1] /u" }, out("[a](/u)").lines)
    assert.same({ "a[1]", "", "Links", "[1] /u" }, out("[a](/u)").lines)
  end)

  it("wraps text with the marker and long targets within the width", function()
    local o = out("aaa [bbb ccc](/u) ddd", 10)
    assert.same({ "aaa bbb", "ccc[1] ddd", "", "Links", "[1] /u" }, o.lines)
    assert.same({ { 1, 4, 7 }, { 2, 0, 3 } }, find(o, "DocPreviewLink"))
    local long = out("[a](" .. ("x"):rep(20) .. ")", 10)
    assert.same({ "a[1]", "", "Links", "[1]", "xxxxxxxxxx", "xxxxxxxxxx" }, long.lines)
  end)

  it("maps Links entries to the block of their first use", function()
    local o = out("a\n\n[b](/1)\nmore\n\n[c](/2)")
    -- "a", "", "b[1] more", "", "c[2]", "", Links, [1], [2]
    local last = o.map[#o.map]
    assert.same({ out_start = 9, out_end = 9, src_start = 6, src_end = 6 }, last)
    assert.same({ out_start = 8, out_end = 8, src_start = 3, src_end = 3 }, o.map[#o.map - 1])
    assert.same({ out_start = 7, out_end = 7, src_start = 3, src_end = 3 }, o.map[#o.map - 2])
  end)

  it("does not change source mapping of the blocks", function()
    local o = out("[b](/1)\n\nx")
    assert.same({ out_start = 1, out_end = 1, src_start = 1, src_end = 1 }, o.map[1])
    assert.same({ out_start = 3, out_end = 3, src_start = 3, src_end = 3 }, o.map[2])
  end)
end)
