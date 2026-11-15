local block = require("doc_preview.markdown.block")
local job = require("doc_preview.core.job")

local function lazy_lines(first, n)
  local lines = { first }
  for _ = 1, n do
    lines[#lines + 1] = "lazy"
  end
  return lines
end

describe("markdown parse yielding", function()
  local function plain_lines(n)
    local lines = {}
    for i = 1, n do
      lines[i] = "line " .. i
    end
    return lines
  end

  it("yields to the event loop during a long parse", function()
    local lines, done, ticks = plain_lines(3000), false, 0
    local timer = vim.uv.new_timer()
    timer:start(
      0,
      1,
      vim.schedule_wrap(function()
        ticks = ticks + 1
      end)
    )
    job.run(function()
      block.parse(lines)
    end, {
      slice_ms = 0,
      on_done = function()
        done = true
      end,
      on_error = error,
    })
    assert.is_true(vim.wait(10000, function()
      return done
    end, 1))
    timer:stop()
    timer:close()
    assert.is_true(ticks >= 1)
  end)

  it("a cancel during the parse aborts it", function()
    local lines, done, calls, j = plain_lines(5000), false, 0, nil
    local yield_point = job.yield_point
    -- Cancel from inside the parse after a fixed number of yield points, so
    -- the test does not depend on timing.
    job.yield_point = function()
      calls = calls + 1
      if calls == 100 then
        j.cancel()
      end
      yield_point()
    end
    local ok, err = pcall(function()
      j = job.run(function()
        block.parse(lines)
      end, {
        slice_ms = 0,
        on_done = function()
          done = true
        end,
        on_error = error,
      })
      vim.wait(200, function()
        return false
      end)
    end)
    job.yield_point = yield_point
    assert.is_true(ok, err)
    assert.is_false(done)
    assert.is_true(calls >= 100 and calls < 200, calls)
  end)

  for name, first in pairs({ quote = "> a", item = "- a" }) do
    it("parses 3000 lazy lines of a " .. name .. " in linear time", function()
      local t = vim.uv.hrtime()
      local doc = block.parse(lazy_lines(first, 3000))
      assert.is_true((vim.uv.hrtime() - t) / 1e9 < 2)
      assert.equals(1, #doc.children)
    end)
  end
end)
