local highlight = require("doc_preview.core.highlight")

describe("core.highlight", function()
  it("defines DocPreviewH1..H6 as default links, idempotently", function()
    highlight.setup()
    highlight.setup()
    for level = 1, 6 do
      local hl = vim.api.nvim_get_hl(0, { name = "DocPreviewH" .. level, link = true })
      assert.is_not_nil(hl.link, "H" .. level)
    end
  end)

  it("defines the inline groups", function()
    highlight.setup()
    assert.is_true(vim.api.nvim_get_hl(0, { name = "DocPreviewEmph" }).italic)
    assert.is_true(vim.api.nvim_get_hl(0, { name = "DocPreviewStrong" }).bold)
    assert.is_true(vim.api.nvim_get_hl(0, { name = "DocPreviewStrike" }).strikethrough)
    assert.is_not_nil(vim.api.nvim_get_hl(0, { name = "DocPreviewCode", link = true }).link)
  end)

  it("defines the link groups as links", function()
    highlight.setup()
    for _, name in ipairs({ "DocPreviewLink", "DocPreviewLinkMark" }) do
      assert.is_not_nil(vim.api.nvim_get_hl(0, { name = name, link = true }).link, name)
    end
  end)

  it("defines the quote group as a link to Comment", function()
    highlight.setup()
    local hl = vim.api.nvim_get_hl(0, { name = "DocPreviewQuote", link = true })
    assert.equals("Comment", hl.link)
  end)

  it("defines the html group as a link to Comment", function()
    highlight.setup()
    local hl = vim.api.nvim_get_hl(0, { name = "DocPreviewHtml", link = true })
    assert.equals("Comment", hl.link)
  end)

  it("defines the list marker group as a link to Special", function()
    highlight.setup()
    local hl = vim.api.nvim_get_hl(0, { name = "DocPreviewListMarker", link = true })
    assert.equals("Special", hl.link)
  end)

  it("defines the image group as a link to Comment", function()
    highlight.setup()
    local hl = vim.api.nvim_get_hl(0, { name = "DocPreviewImage", link = true })
    assert.equals("Comment", hl.link)
  end)

  it("defines the footnote reference group as a link to Special", function()
    highlight.setup()
    local hl = vim.api.nvim_get_hl(0, { name = "DocPreviewFootnoteRef", link = true })
    assert.equals("Special", hl.link)
  end)

  it("lets a colour scheme override the default", function()
    vim.api.nvim_set_hl(0, "DocPreviewH3", { fg = "#ff0000" })
    highlight.setup()
    assert.equals(0xff0000, vim.api.nvim_get_hl(0, { name = "DocPreviewH3" }).fg)
    vim.api.nvim_set_hl(0, "DocPreviewH3", {})
  end)

  it("applies spans as extmarks", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two words" })
    local ns = vim.api.nvim_create_namespace("doc_preview.test.highlight")
    highlight.apply(buf, ns, {
      { line = 1, col_start = 0, col_end = 3, hl_group = "DocPreviewH1" },
      { line = 2, col_start = 0, col_end = 9, hl_group = "DocPreviewH2" },
    })
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    assert.equals(2, #marks)
    assert.equals(0, marks[1][2])
    assert.equals("DocPreviewH1", marks[1][4].hl_group)
    assert.equals(3, marks[1][4].end_col)
    assert.equals(1, marks[2][2])
    assert.equals("DocPreviewH2", marks[2][4].hl_group)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)

describe("core.highlight tables", function()
  it("defines the table groups as default links", function()
    highlight.setup()
    local border = vim.api.nvim_get_hl(0, { name = "DocPreviewTableBorder", link = true })
    assert.equals("Comment", border.link)
    local header = vim.api.nvim_get_hl(0, { name = "DocPreviewTableHeader", link = true })
    assert.is_true(header.link == "Title" or header.link == "Special")
  end)
end)

describe("core.highlight diagram groups", function()
  it("defines the diagram and errbox groups as default links", function()
    highlight.setup()
    for _, name in ipairs({
      "DocPreviewDiagramBorder",
      "DocPreviewDiagramEdge",
      "DocPreviewDiagramLabel",
      "DocPreviewErrbox",
    }) do
      assert.is_not_nil(vim.api.nvim_get_hl(0, { name = name, link = true }).link, name)
    end
  end)
end)
