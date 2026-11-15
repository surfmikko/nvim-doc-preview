-- The banned-API and size gates must catch planted violations (doc/testing.md 5).
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")

local function plant(lines)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  vim.fn.writefile(lines, dir .. "/x.lua")
  return dir
end

local function run(tool, dir, env)
  local out = vim.fn.system((env or "") .. "sh " .. root .. "/tools/" .. tool .. " " .. dir)
  return vim.v.shell_error, out
end

describe("tools/check-banned", function()
  local banned = {
    'os.execute("ls")',
    'io.popen("ls")',
    'vim.system({ "ls" })',
    'vim.fn.jobstart("ls")',
    'local f = load("return 1")',
    'local f = loadstring("return 1")',
    'local x = require("some.other")',
  }
  for _, line in ipairs(banned) do
    it("catches " .. line, function()
      local code, out = run("check-banned", plant({ line }))
      assert.are.equal(1, code)
      assert.is_truthy(out:find("x.lua:1:", 1, true))
    end)
  end

  it("accepts clean code", function()
    local lines = {
      'local m = require("doc_preview.core.out")',
      'local n = require "doc_preview"',
      "vim.g.loaded_doc_preview = true",
      "local x = tbl.load(1)",
    }
    assert.are.equal(0, (run("check-banned", plant(lines))))
  end)

  it("accepts the repository code", function()
    assert.are.equal(0, (run("check-banned", root .. "/lua " .. root .. "/plugin")))
  end)
end)

describe("tools/check-size", function()
  it("fails over the limit and passes at it", function()
    local dir = plant({ "a", "b", "c" })
    assert.are.equal(1, (run("check-size", dir, "MAX=2 ")))
    assert.are.equal(0, (run("check-size", dir, "MAX=3 ")))
  end)

  it("accepts the repository code", function()
    assert.are.equal(0, (run("check-size", root .. "/lua")))
  end)
end)
