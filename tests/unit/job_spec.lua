local job = require("doc_preview.core.job")

local function busy(ms)
  local stop = vim.uv.hrtime() + ms * 1e6
  while vim.uv.hrtime() < stop do
  end
end

describe("core.job", function()
  it("runs asynchronously and delivers the result", function()
    local result
    job.run(function()
      return 42
    end, {
      slice_ms = 8,
      on_done = function(r)
        result = r
      end,
      on_error = error,
    })
    assert.is_nil(result)
    assert.is_true(vim.wait(1000, function()
      return result ~= nil
    end))
    assert.equals(42, result)
  end)

  it("yields at yield_point once the slice is used up", function()
    local done, ticks = false, 0
    local timer = vim.uv.new_timer()
    timer:start(
      0,
      5,
      vim.schedule_wrap(function()
        ticks = ticks + 1
      end)
    )
    job.run(function()
      for _ = 1, 20 do
        busy(5)
        job.yield_point()
      end
    end, {
      slice_ms = 1,
      on_done = function()
        done = true
      end,
      on_error = error,
    })
    assert.is_true(vim.wait(2000, function()
      return done
    end))
    timer:stop()
    timer:close()
    assert.is_true(ticks >= 3, "loop timer starved: " .. ticks)
  end)

  it("does not yield within a slice", function()
    local resumes = 0
    local done = false
    job.run(function()
      resumes = resumes + 1
      for _ = 1, 100 do
        job.yield_point()
      end
    end, {
      slice_ms = 1000,
      on_done = function()
        done = true
      end,
      on_error = error,
    })
    vim.wait(1000, function()
      return done
    end)
    assert.equals(1, resumes)
  end)

  it("cancel stops the job and never calls back", function()
    local steps, called = 0, false
    local j = job.run(function()
      while true do
        steps = steps + 1
        busy(2)
        job.yield_point()
      end
    end, {
      slice_ms = 1,
      on_done = function()
        called = true
      end,
      on_error = function()
        called = true
      end,
    })
    vim.wait(30, function()
      return steps > 2
    end)
    j.cancel()
    local seen = steps
    vim.wait(50)
    assert.equals(seen, steps)
    assert.is_false(called)
    assert.is_true(j.timer:is_closing())
  end)

  it("reports errors through on_error and closes its timer", function()
    local err
    local j = job.run(function()
      error("boom")
    end, {
      slice_ms = 8,
      on_done = function() end,
      on_error = function(e)
        err = e
      end,
    })
    assert.is_true(vim.wait(1000, function()
      return err ~= nil
    end))
    assert.matches("boom", err)
    assert.is_true(j.timer:is_closing())
  end)

  it("yield_point is a no-op outside a job", function()
    assert.has_no.errors(job.yield_point)
  end)
end)
