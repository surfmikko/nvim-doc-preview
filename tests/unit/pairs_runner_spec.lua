local runner = require("pairs.runner")

local function write(path, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(lines, path)
end

local function case(root, name, input, expected)
  write(root .. "/markdown/s/" .. name .. ".in", input)
  if expected then
    write(root .. "/markdown/s/" .. name .. ".expected", expected)
  end
end

describe("pairs.runner", function()
  local root
  before_each(function()
    root = vim.fn.tempname()
    case(root, "ok", { "# a" }, { "<h1>a</h1>", "" })
    case(root, "bad", { "# a" }, { "<h2>a</h2>" })
    case(root, "skipme", { "# a" }, { "<h2>a</h2>" })
    case(root, "pending", { "# a" })
  end)
  after_each(function()
    vim.fn.delete(root, "rf")
  end)

  it("counts pass, fail, skipped and pending", function()
    write(root .. "/markdown/skip.lua", { 'return { ["s/skipme"] = "why" }' })
    local r = runner.run_suite(root, "markdown", "s")
    assert.equals(1, r.pass)
    assert.equals(4, r.total)
    assert.same({ "s/bad" }, vim.tbl_keys(r.failed))
    assert.same({ ["s/skipme"] = "why" }, r.skipped)
    assert.same({ "s/pending" }, r.pending)
    assert.same({}, r.stale)
    assert.equals("commonmark-s: 1/4 pass, 1 skipped, 1 pending (no .expected)", runner.summary(r))
  end)

  it("flags stale skips: unknown case and passing case", function()
    write(root .. "/markdown/skip.lua", { 'return { ["s/ghost"] = "x", ["s/ok"] = "y" }' })
    local r = runner.run_suite(root, "markdown", "s")
    assert.same({ "s/ghost (no such case)", "s/ok (passes but is skipped)" }, r.stale)
  end)

  it("enforces the threshold", function()
    write(root .. "/markdown/threshold.lua", { "return { s = 2 }" })
    local r = runner.run_suite(root, "markdown", "s")
    assert.equals(1, #r.errors)
  end)

  it("reports unsupported kinds in a failure message", function()
    case(root, "u", { "a" }, { "<p>a</p>" })
    local frontend = require("doc_preview.markdown.block")
    local orig = frontend.parse
    frontend.parse = function()
      return { kind = "document", children = { { kind = "md:x" } } }
    end
    local r = runner.run_suite(root, "markdown", "s")
    frontend.parse = orig
    assert.truthy(r.failed["s/u"]:find("unsupported: md:x", 1, true))
  end)
end)

describe("pairs.runner mermaid", function()
  it("compares facts and reports parse errors as facts", function()
    local root = vim.fn.tempname()
    local dir = root .. "/mermaid/s/"
    write(dir .. "ok.in", { "graph LR", "A --> B" })
    write(dir .. "ok.expected", {
      "direction LR",
      'node A rect "A"',
      'node B rect "B"',
      "edge A B solid head=arrow tail=none length=1",
    })
    write(dir .. "err.in", { "graph LR", "A -->" })
    write(dir .. "err.expected", { "error: line 2: syntax error: A -->" })
    write(dir .. "bad.in", { "graph LR", "A" })
    write(dir .. "bad.expected", { "direction TD" })
    local r = runner.run_suite(root, "mermaid", "s")
    vim.fn.delete(root, "rf")
    assert.equals(2, r.pass)
    assert.same({ "s/bad" }, vim.tbl_keys(r.failed))
    assert.equals("mermaid-s: 2/3 pass, 0 skipped", runner.summary(r))
  end)
end)
