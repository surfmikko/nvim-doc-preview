local block = require("doc_preview.markdown.block")
local render = require("doc_preview.document.render")
local text = require("doc_preview.core.text")

local WIDTH = 1000

local function out(lines)
  return render.render(block.parse(lines), { width = WIDTH })
end

local function check(o)
  assert.is_true(#o.lines > 0)
  local found = false
  for _, line in ipairs(o.lines) do
    assert.is_true(text.width(line) <= WIDTH)
    found = found or line:find("deep", 1, true) ~= nil
  end
  assert.is_true(found)
end

describe("document.render nesting", function()
  it("renders 200 nested quote levels", function()
    check(out({ ("> "):rep(200) .. "deep" }))
  end)

  it("renders 200 nested list levels", function()
    local lines = {}
    for i = 0, 199 do
      lines[#lines + 1] = (" "):rep(2 * i) .. "- " .. (i == 199 and "deep" or "item")
    end
    check(out(lines))
  end)
end)
