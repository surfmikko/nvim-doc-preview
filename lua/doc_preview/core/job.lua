-- Coroutine job runner: runs a function in slices on the main loop so
-- input stays responsive (doc/architecture.md 5.3). Cancellable.
local M = {}

local current -- slice state of the job being resumed, nil outside a job

-- Call from long loops: yields to the event loop once the slice is used up.
-- No-op outside a job, so job-aware code stays callable synchronously.
function M.yield_point()
  if current and vim.uv.hrtime() >= current.deadline then
    coroutine.yield()
  end
end

---@param fn fun(): any
---@param opts { slice_ms: number, on_done: fun(result: any), on_error: fun(err: string) }
---@return { cancel: fun(), timer: userdata }
function M.run(fn, opts)
  local co = coroutine.create(fn)
  local timer = vim.uv.new_timer()
  local job = { cancelled = false, timer = timer }

  local function finish()
    if not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end

  local step

  -- one-shot 0 ms timer per resume, so input gets a turn between slices
  local function schedule()
    timer:start(0, 0, vim.schedule_wrap(step))
  end

  function step()
    if job.cancelled then
      return
    end
    current = { deadline = vim.uv.hrtime() + opts.slice_ms * 1e6 }
    local ok, res = coroutine.resume(co)
    current = nil
    if not ok then
      finish()
      opts.on_error(res)
    elseif coroutine.status(co) == "dead" then
      finish()
      opts.on_done(res)
    else
      schedule()
    end
  end

  function job.cancel()
    job.cancelled = true
    finish()
  end

  schedule()
  return job
end

return M
