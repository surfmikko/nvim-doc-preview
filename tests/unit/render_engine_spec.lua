local block = require("doc_preview.markdown.block")
local out = require("doc_preview.core.out")
local render = require("doc_preview.document.render")

local function run(src, ctx)
  return render.render(block.parse(src), ctx or { width = 30 })
end

local SRC = { "intro", "", "```mermaid", "flowchart TD", "A[x]", "```", "", "outro" }

describe("document.render engines", function()
  local saved
  before_each(function()
    saved = render.engines.mermaid.render
  end)
  after_each(function()
    render.engines.mermaid.render = saved
  end)

  it("renders a mermaid block with one atomic map entry over the fences", function()
    local o = run(SRC)
    assert.equals("┌───┐", o.lines[3])
    assert.is_nil(table.concat(o.lines, "\n"):find("```", 1, true))
    local entry
    for _, m in ipairs(o.map) do
      if m.src_start == 3 then
        entry = m
      end
    end
    assert.same({ out_start = 3, out_end = 5, src_start = 3, src_end = 6 }, entry)
    assert.equals(3, o:src_to_out(3))
    assert.equals(5, o:src_to_out(6))
  end)

  it("shows the block as plain code when engines.mermaid is false", function()
    local o = run(SRC, { width = 30, engines = { mermaid = false } })
    assert.same({ "intro", "", "flowchart TD", "A[x]", "", "outro" }, o.lines)
  end)

  it("replaces a raising engine by an errbox and keeps the rest", function()
    render.engines.mermaid.render = function()
      error("boom", 0)
    end
    local o = run(SRC)
    assert.equals("intro", o.lines[1])
    assert.equals("outro", o.lines[#o.lines])
    assert.is_truthy(table.concat(o.lines, "\n"):find("boom", 1, true))
  end)

  it("replaces an engine result that is invalid or too wide", function()
    for _, bad in ipairs({ "garbage", { lines = { ("x"):rep(99) }, spans = {}, map = {} } }) do
      render.engines.mermaid.render = function()
        return bad
      end
      local o = run(SRC)
      assert.is_truthy(table.concat(o.lines, "\n"):find("invalid output", 1, true))
      assert.is_true(out.valid(o, 30))
    end
  end)
end)
