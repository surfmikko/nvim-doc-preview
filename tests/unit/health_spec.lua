local health = require("doc_preview.health")

local function run_check()
  local seen = { ok = {}, warn = {}, error = {} }
  local saved = {}
  for _, name in ipairs({ "start", "info", "ok", "warn", "error" }) do
    saved[name] = vim.health[name]
  end
  vim.health.start = function() end
  vim.health.info = function() end
  for _, level in ipairs({ "ok", "warn", "error" }) do
    vim.health[level] = function(msg)
      table.insert(seen[level], msg)
    end
  end
  local ok, err = pcall(health.check)
  for name, fn in pairs(saved) do
    vim.health[name] = fn
  end
  assert.is_true(ok, err)
  return seen
end

describe("health", function()
  it("reports no errors with default config", function()
    require("doc_preview.config").setup({})
    vim.cmd("runtime plugin/doc_preview.lua")
    local seen = run_check()
    assert.same({}, seen.error)
    assert.is_true(#seen.ok >= 3)
  end)

  it("has a semver version", function()
    assert.is_truthy(require("doc_preview").version:match("^%d+%.%d+%.%d+$"))
  end)
end)
