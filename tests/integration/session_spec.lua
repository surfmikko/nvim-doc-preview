local doc_preview = require("doc_preview")
local render = require("doc_preview.document.render")
local job = require("doc_preview.core.job")

vim.cmd("runtime plugin/doc_preview.lua")

local function busy_ms(ms)
  local stop = vim.uv.hrtime() + ms * 1e6
  while vim.uv.hrtime() < stop do
  end
end

local function set_source(lines)
  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function preview_lines(s)
  return vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false)
end

-- Fires the same autocmd the real edit would; headless has no typing.
local function edit(buf, lines)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
end

-- Test hook: the paragraph whose text is "slow" takes ~total_ms, in slices.
local function slow_block(total_ms)
  render.test_hook = function(node)
    if node.inlines[1].value == "slow" then
      local stop = vim.uv.hrtime() + total_ms * 1e6
      while vim.uv.hrtime() < stop do
        busy_ms(2)
        job.yield_point()
      end
    end
  end
end

local rendered
local function augroups()
  local n = 0
  for _, g in ipairs(vim.api.nvim_get_autocmds({ event = "TextChanged" })) do
    if g.group_name and g.group_name:match("^DocPreview") then
      n = n + 1
    end
  end
  return n
end

describe("DocPreview async pipeline", function()
  before_each(function()
    doc_preview.setup({ debounce_ms = 20, slice_ms = 2 })
    rendered = {}
    vim.api.nvim_create_autocmd("User", {
      group = vim.api.nvim_create_augroup("DocPreviewTest", { clear = true }),
      pattern = "DocPreviewRendered",
      callback = function(ev)
        rendered[#rendered + 1] = ev.data.generation
      end,
    })
  end)

  after_each(function()
    render.test_hook = nil
    vim.api.nvim_del_augroup_by_name("DocPreviewTest")
    pcall(vim.cmd, "only")
  end)

  it("open renders the buffer asynchronously into a read-only split", function()
    local src = set_source({ "hello", "world", "", "second" })
    vim.cmd("DocPreview open")
    local s = doc_preview.session(src)
    assert.is_not_nil(s)
    assert.same({ "" }, preview_lines(s)) -- nothing rendered synchronously
    assert.is_true(doc_preview.wait(s, 2000))
    assert.same({ "hello world", "", "second" }, preview_lines(s))
    assert.is_false(vim.bo[s.prev_buf].modifiable)
    assert.equals(2, #vim.api.nvim_tabpage_list_wins(0))
    assert.equals(1, #rendered)
    doc_preview.close()
  end)

  it("close and toggle tear down the session without leaks", function()
    local src = set_source({ "a" })
    vim.cmd("DocPreview toggle")
    local s = doc_preview.session(src)
    doc_preview.wait(s, 2000)
    vim.cmd("DocPreview toggle")
    assert.is_nil(doc_preview.session(src))
    assert.is_false(vim.api.nvim_buf_is_valid(s.prev_buf))
    assert.is_false(vim.api.nvim_win_is_valid(s.prev_win))
    assert.is_true(s.timer:is_closing())
    assert.is_nil(s.job)
    assert.equals(0, augroups())
    assert.equals(1, #vim.api.nvim_tabpage_list_wins(0))
  end)

  it("closing the preview window tears the session down", function()
    local src = set_source({ "a" })
    vim.cmd("DocPreview open")
    local s = doc_preview.session(src)
    doc_preview.wait(s, 2000)
    vim.api.nvim_win_close(s.prev_win, true)
    assert.is_nil(doc_preview.session(src))
    assert.is_true(s.timer:is_closing())
    assert.equals(0, augroups())
  end)

  it("deleting the source buffer closes the preview", function()
    local src = set_source({ "a" })
    vim.cmd("DocPreview open")
    local s = doc_preview.session(src)
    doc_preview.wait(s, 2000)
    vim.cmd("enew")
    vim.cmd("bwipeout! " .. src)
    assert.is_nil(doc_preview.session(src))
    assert.is_false(vim.api.nvim_win_is_valid(s.prev_win))
    assert.equals(0, augroups())
  end)

  it("a text change re-renders after the debounce", function()
    local src = set_source({ "one" })
    vim.cmd("DocPreview open")
    local s = doc_preview.session(src)
    doc_preview.wait(s, 2000)
    edit(src, { "two" })
    assert.same({ "one" }, preview_lines(s)) -- debounced, not yet
    assert.is_true(doc_preview.wait(s, 2000))
    assert.same({ "two" }, preview_lines(s))
  end)

  it("a slow block does not block the event loop", function()
    slow_block(300)
    local src = set_source({ "fast", "", "slow" })
    local ticks = 0
    local timer = vim.uv.new_timer()
    timer:start(
      0,
      10,
      vim.schedule_wrap(function()
        ticks = ticks + 1
      end)
    )
    vim.cmd("DocPreview open")
    local s = doc_preview.session(src)
    assert.is_true(doc_preview.wait(s, 5000))
    timer:stop()
    timer:close()
    -- A blocked loop gives 0-1 ticks over the 300 ms block; a yielding job
    -- gives about 20+ on a fast machine. Slow CI runners saw 9, so the bar is
    -- low: it only has to tell "yielded" from "blocked".
    assert.is_true(ticks >= 3, "event loop starved, ticks=" .. ticks)
    assert.same({ "fast", "", "slow" }, preview_lines(s))
  end)

  it("a second edit cancels the running job and only its result lands", function()
    local src = set_source({ "x" })
    vim.cmd("DocPreview open")
    local s = doc_preview.session(src)
    doc_preview.wait(s, 2000)
    rendered = {}
    slow_block(500)
    edit(src, { "slow" })
    assert.is_true(vim.wait(1000, function()
      return s.job ~= nil
    end, 5))
    local first_job = s.job
    vim.wait(60) -- let the slow job start slicing
    render.test_hook = nil
    edit(src, { "final" })
    assert.is_true(first_job.cancelled)
    assert.is_true(doc_preview.wait(s, 5000))
    assert.same({ "final" }, preview_lines(s))
    assert.equals(1, #rendered)
    assert.equals(s.generation, rendered[1])
  end)

  it("a result finishing after a newer edit is never applied", function()
    local src = set_source({ "a" })
    vim.cmd("DocPreview open")
    local s = doc_preview.session(src)
    doc_preview.wait(s, 2000)
    edit(src, { "b" })
    doc_preview.wait(s, 2000)
    assert.same({ "b" }, preview_lines(s))
    -- stale generation: bump without cancelling, then deliver the old job's result
    local before = #rendered
    local session = require("doc_preview.session")
    session.render(s) -- job for generation N
    s.generation = s.generation + 1 -- newer change arrives
    vim.wait(100)
    assert.equals(before, #rendered)
    assert.same({ "b" }, preview_lines(s))
  end)

  it("a render failure notifies, clears the job and the next edit renders", function()
    local src = set_source({ "hello" })
    local orig, notified = render.render, {}
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      notified[#notified + 1] = { msg = msg, level = level }
    end
    render.render = function()
      error("boom")
    end
    vim.cmd("DocPreview open")
    local s = doc_preview.session(src)
    assert.is_true(doc_preview.wait(s, 2000))
    render.render = orig
    vim.notify = orig_notify
    assert.is_nil(s.job)
    assert.equals(1, #notified)
    assert.truthy(notified[1].msg:find("render failed", 1, true))
    assert.truthy(notified[1].msg:find("boom", 1, true))
    assert.equals(vim.log.levels.ERROR, notified[1].level)
    edit(src, { "again" })
    assert.is_true(doc_preview.wait(s, 2000))
    assert.same({ "again" }, preview_lines(s))
  end)
end)
