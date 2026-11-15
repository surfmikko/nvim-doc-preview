local config = require("doc_preview.config")
local doc_preview = require("doc_preview")
local job = require("doc_preview.core.job")
local render = require("doc_preview.document.render")
local session = require("doc_preview.session")

vim.cmd("runtime plugin/doc_preview.lua")

local LIMIT = 20

local function paragraphs(n, tag)
  local t = {}
  for i = 1, n do
    t[#t + 1] = (tag or "p") .. i
  end
  return t
end

local function open(lines)
  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  session.open(buf)
  return buf, session.get(buf)
end

local function edit(buf, lines)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
end

local function save(buf)
  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = buf })
end

local function preview(s)
  return vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false)
end

describe("large file guard", function()
  local warnings, rendered, orig_notify

  before_each(function()
    config.setup({ large_file_lines = LIMIT, debounce_ms = 20, slice_ms = 2 })
    warnings, rendered = {}, 0
    orig_notify = vim.notify
    vim.notify = function(msg, level)
      if level == vim.log.levels.WARN then
        table.insert(warnings, msg)
      end
    end
    vim.api.nvim_create_autocmd("User", {
      pattern = "DocPreviewRendered",
      group = vim.api.nvim_create_augroup("LargeSpec", { clear = true }),
      callback = function()
        rendered = rendered + 1
      end,
    })
  end)

  after_each(function()
    render.test_hook = nil
    vim.notify = orig_notify
    pcall(vim.api.nvim_del_augroup_by_name, "LargeSpec")
    config.setup({})
    pcall(vim.cmd, "only!")
  end)

  it("(a) warns once at open and still renders once", function()
    local _, s = open(paragraphs(LIMIT + 5))
    assert.equals(1, #warnings)
    assert.is_truthy(warnings[1]:find("25 lines exceeds large_file_lines (20)", 1, true))
    assert.is_true(session.wait(s, 2000))
    assert.equals(1, rendered)
    assert.equals(1, #warnings)
  end)

  it("(b) edits over the threshold do nothing", function()
    local buf, s = open(paragraphs(LIMIT + 5))
    session.wait(s, 2000)
    local before = preview(s)
    for i = 1, 3 do
      edit(buf, paragraphs(LIMIT + 5, "e" .. i .. "_"))
    end
    assert.is_true(session.wait(s, 2000))
    vim.wait(60) -- longer than the debounce
    assert.equals(1, rendered)
    assert.equals(1, #warnings)
    assert.same(before, preview(s))
  end)

  it("(c) a save renders the new content", function()
    local buf, s = open(paragraphs(LIMIT + 5))
    session.wait(s, 2000)
    edit(buf, paragraphs(LIMIT + 5, "new"))
    local path = vim.fn.tempname() .. ".md"
    -- Name the buffer first: `:write path` on an unnamed buffer fires no BufWritePost for it.
    vim.cmd("silent file " .. vim.fn.fnameescape(path))
    vim.cmd("silent write")
    assert.is_true(session.wait(s, 2000))
    assert.equals(2, rendered)
    assert.is_truthy(table.concat(preview(s), "\n"):find("new1", 1, true))
    vim.fn.delete(path)
  end)

  it("(d) under the threshold edits render and never warn", function()
    local buf, s = open(paragraphs(3))
    session.wait(s, 2000)
    edit(buf, paragraphs(4, "q"))
    session.wait(s, 2000)
    assert.equals(2, rendered)
    assert.is_truthy(table.concat(preview(s), "\n"):find("q4", 1, true))
    save(buf)
    session.wait(s, 2000)
    assert.equals(2, rendered, "save under the threshold must not render again")
    assert.equals(0, #warnings)
  end)

  it("(e) growing past the threshold warns once, shrinking resumes", function()
    local buf, s = open(paragraphs(3))
    session.wait(s, 2000)
    edit(buf, paragraphs(LIMIT + 1))
    assert.equals(1, #warnings)
    session.wait(s, 2000)
    vim.wait(60)
    assert.equals(1, rendered)
    edit(buf, paragraphs(LIMIT + 2))
    assert.equals(1, #warnings)
    edit(buf, paragraphs(3, "s"))
    assert.is_true(session.wait(s, 2000))
    assert.equals(2, rendered)
    assert.is_truthy(table.concat(preview(s), "\n"):find("s3", 1, true))
    edit(buf, paragraphs(LIMIT + 1))
    assert.equals(1, #warnings, "one warning per session")
  end)

  it("(f) the threshold is configurable and validated", function()
    config.setup({ large_file_lines = 100, debounce_ms = 20, slice_ms = 2 })
    local buf, s = open(paragraphs(LIMIT + 5))
    session.wait(s, 2000)
    assert.equals(0, #warnings)
    edit(buf, paragraphs(LIMIT + 6))
    session.wait(s, 2000)
    assert.equals(2, rendered)
    local ok = pcall(config.setup, { large_file_lines = 0 })
    assert.is_false(ok)
    assert.equals(100, config.options.large_file_lines)
  end)

  it("(g) scroll and cursor sync work in a large buffer", function()
    local lines = {}
    for i = 1, 40 do
      vim.list_extend(lines, { "p" .. i, "", "" })
    end
    local _, s = open(lines)
    assert.is_true(session.wait(s, 2000))
    vim.wait(50)
    vim.api.nvim_win_set_cursor(s.src_win, { 31, 0 }) -- p11
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.src_buf })
    assert.equals(21, vim.api.nvim_win_get_cursor(s.prev_win)[1])
  end)

  it("(h) a save cancels a running render and a pending debounce", function()
    render.test_hook = function(node)
      if node.inlines[1].value == "slow" then
        local stop = vim.uv.hrtime() + 300e6
        while vim.uv.hrtime() < stop do
          job.yield_point()
        end
      end
    end
    local lines = paragraphs(LIMIT + 5)
    lines[1] = "slow"
    local buf, s = open(lines)
    vim.wait(30, function()
      return false
    end)
    assert.is_truthy(s.job, "initial render still running")
    local gen = s.generation
    edit(buf, paragraphs(LIMIT + 5, "fresh"))
    assert.equals(gen, s.generation, "edit over the threshold does not cancel")
    save(buf)
    assert.is_true(s.generation > gen, "save cancels the running job")
    assert.is_true(s.pending)
    local gen2 = s.generation
    save(buf)
    assert.is_true(s.generation > gen2, "second save restarts the debounce")
    assert.is_true(session.wait(s, 3000))
    assert.equals(1, rendered, "stale renders are never applied")
    assert.is_truthy(table.concat(preview(s), "\n"):find("fresh1", 1, true))
  end)

  it("(i) leaves no autocmds after close", function()
    local buf, s = open(paragraphs(LIMIT + 5))
    local group = s.augroup
    session.wait(s, 2000)
    doc_preview.close()
    assert.is_false(pcall(vim.api.nvim_get_autocmds, { group = group }))
    assert.same({}, vim.api.nvim_get_autocmds({ buffer = buf, event = "BufWritePost" }))
  end)
end)
