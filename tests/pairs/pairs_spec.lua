-- Runs every committed reference-pair suite (doc/testing.md 2).
local runner = require("pairs.runner")

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")

local function keys(t)
  local out = {}
  for k, v in pairs(t) do
    out[#out + 1] = k .. ": " .. v
  end
  table.sort(out)
  return out
end

for fmt in pairs(runner.frontends) do
  for _, suite in ipairs(runner.suites(root, fmt)) do
    describe("pairs " .. fmt .. "/" .. suite, function()
      it("meets its threshold with no failures or stale skips", function()
        local r = runner.run_suite(root, fmt, suite)
        print(runner.summary(r))
        for key, reason in pairs(r.skipped) do
          print("  skipped " .. key .. ": " .. reason)
        end
        local problems = vim.list_extend(vim.list_extend(keys(r.failed), r.stale), r.errors)
        assert.same({}, problems)
      end)
    end)
  end
end
