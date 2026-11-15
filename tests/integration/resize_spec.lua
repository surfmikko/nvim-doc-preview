local doc_preview = require("doc_preview")
local session = require("doc_preview.session")

vim.cmd("runtime plugin/doc_preview.lua")

local function content()
  local words = {}
  for i = 1, 60 do
    words[i] = "word" .. i
  end
  local para = table.concat(words, " ")
  return {
    "# Heading with quite a few words so that it needs to wrap around at narrow widths",
    "",
    para,
    "",
    "| name | description |",
    "| ---- | ----------- |",
    "| alpha | a fairly long description that must wrap inside its cell |",
    "| beta | another fairly long description for the second row here |",
    "",
    "```lua",
    "local very_long_name = some_function(argument_one, argument_two, argument_three)",
    "```",
    "",
    "> " .. para,
  }
end

local function open()
  vim.cmd("enew")
  local src = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(src, 0, -1, false, content())
  vim.cmd("DocPreview open")
  local s = doc_preview.session(src)
  assert.is_true(doc_preview.wait(s, 2000))
  return s
end

local function max_width(s)
  local w = 0
  for _, l in ipairs(vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false)) do
    w = math.max(w, vim.fn.strdisplaywidth(l))
  end
  return w
end

local function resize_to(s, n)
  vim.api.nvim_win_set_width(s.prev_win, n)
  vim.api.nvim_exec_autocmds("VimResized", {})
  assert.is_true(doc_preview.wait(s, 2000))
end

describe("DocPreview resize", function()
  local old_max
  before_each(function()
    old_max = require("doc_preview.config").options.max_width
    require("doc_preview.config").options.max_width = 200
    vim.o.columns = 160
  end)
  after_each(function()
    require("doc_preview.config").options.max_width = old_max
    pcall(vim.cmd, "only")
  end)

  it("re-renders at the new width without overflow", function()
    local s = open()
    local gen = s.generation
    local rendered = 0
    local au = vim.api.nvim_create_autocmd("User", {
      pattern = "DocPreviewRendered",
      callback = function()
        rendered = rendered + 1
      end,
    })
    local before = #vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false)
    resize_to(s, 30)
    vim.api.nvim_del_autocmd(au)
    assert.are.equal(30, s.width)
    assert.is_true(s.generation > gen)
    assert.are.equal(1, rendered)
    assert.is_true(#vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false) > before)
    assert.is_true(max_width(s) <= 30)
  end)

  it("round-trips narrow then wide", function()
    local s = open()
    local wide = vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false)
    local w0 = s.width
    resize_to(s, 25)
    assert.is_true(max_width(s) <= 25)
    resize_to(s, w0)
    assert.are.same(wide, vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false))
  end)

  it("does nothing when the width is unchanged", function()
    local s = open()
    local gen = s.generation
    vim.api.nvim_exec_autocmds("VimResized", {})
    vim.api.nvim_exec_autocmds("WinResized", { data = {} })
    assert.are.equal(gen, s.generation)
  end)

  it("ignores a height-only resize", function()
    local s = open()
    local gen = s.generation
    vim.api.nvim_win_set_height(s.prev_win, 5)
    vim.api.nvim_exec_autocmds("VimResized", {})
    assert.are.equal(gen, s.generation)
  end)

  it("does nothing when width is beyond max_width", function()
    require("doc_preview.config").options.max_width = 20
    local s = open()
    assert.are.equal(20, s.width)
    local gen = s.generation
    vim.api.nvim_win_set_width(s.prev_win, s.width + 20)
    vim.api.nvim_exec_autocmds("VimResized", {})
    assert.are.equal(gen, s.generation)
  end)

  -- Headless nvim delivers WinResized only to an attached UI, so the real
  -- event (with its v:event.windows filter) runs in a child nvim with one.
  local CHILD = [[
    vim.cmd("runtime plugin/doc_preview.lua")
    local dp = require("doc_preview")
    vim.cmd("enew")
    local src = vim.api.nvim_get_current_buf()
    local words = {}
    for i = 1, 60 do words[i] = "word" .. i end
    vim.api.nvim_buf_set_lines(src, 0, -1, false, { table.concat(words, " ") })
    vim.cmd("DocPreview open")
    local s = dp.session(src)
    dp.wait(s, 2000)
    vim.cmd("wincmd p")
    vim.cmd("belowright new")
    _G.other = vim.api.nvim_get_current_win()
    _G.s = s
    _G.calls = 0
    local inner = s.handlers.resized
    s.handlers.resized = function(x)
      _G.calls = _G.calls + 1
      inner(x)
    end
    return s.generation
  ]]

  local function child_state(ch, code)
    return vim.rpcrequest(ch, "nvim_exec_lua", code, {})
  end

  local function child_wait(ch, cond)
    for _ = 1, 100 do
      vim.rpcnotify(ch, "nvim_command", "redraw")
      vim.wait(20)
      if child_state(ch, "return " .. cond) then
        return true
      end
    end
    return false
  end

  local function spawn()
    local cmd = { vim.v.progpath, "--embed", "--headless", "--noplugin" }
    vim.list_extend(cmd, { "-u", "tests/minimal_init.lua" })
    local ch = vim.fn.jobstart(cmd, { rpc = true })
    vim.rpcrequest(ch, "nvim_ui_attach", 120, 40, {})
    return ch
  end

  it("reacts to a real WinResized of the preview window", function()
    local ch = spawn()
    local gen = child_state(ch, CHILD)
    child_state(ch, "vim.api.nvim_win_set_width(_G.s.prev_win, 35)")
    assert.is_true(child_wait(ch, "_G.s.width == 35"))
    assert.is_true(child_state(ch, "return _G.calls") >= 1)
    assert.is_true(child_state(ch, "return _G.s.generation") > gen)
    vim.fn.jobstop(ch)
  end)

  it("ignores a real WinResized that lists only other windows", function()
    local ch = spawn()
    local gen = child_state(ch, CHILD)
    child_state(ch, "vim.api.nvim_win_set_height(_G.other, 3)")
    child_wait(ch, "false")
    assert.are.equal(0, child_state(ch, "return _G.calls"))
    assert.are.equal(gen, child_state(ch, "return _G.s.generation"))
    vim.fn.jobstop(ch)
  end)

  it("cancels a running job on resize", function()
    local s = open()
    session.render(s)
    local running = s.job
    assert.is_truthy(running)
    local gen = s.generation
    resize_to(s, 28)
    assert.is_true(s.generation > gen)
    assert.is_true(max_width(s) <= 28)
  end)

  it("keeps the cursor mapped after re-render", function()
    local s = open()
    vim.api.nvim_set_current_win(s.src_win)
    vim.api.nvim_win_set_cursor(s.src_win, { 3, 0 })
    resize_to(s, 30)
    local row = vim.api.nvim_win_get_cursor(s.prev_win)[1]
    local text = vim.api.nvim_buf_get_lines(s.prev_buf, row - 1, row, false)[1]
    assert.is_truthy(text:find("word"))
  end)

  it("re-syncs when the preview has focus", function()
    local s = open()
    vim.api.nvim_win_set_cursor(s.src_win, { 3, 0 })
    vim.api.nvim_set_current_win(s.prev_win)
    resize_to(s, 30)
    local row = vim.api.nvim_win_get_cursor(s.prev_win)[1]
    local text = vim.api.nvim_buf_get_lines(s.prev_buf, row - 1, row, false)[1]
    assert.is_truthy(text:find("word"))
  end)

  it("leaves no autocmds after close", function()
    local s = open()
    local group = s.augroup
    doc_preview.close(s)
    assert.is_false(pcall(vim.api.nvim_get_autocmds, { group = group }))
  end)
end)
