local doc_preview = require("doc_preview")
local render = require("doc_preview.document.render")
local sync = require("doc_preview.sync")

vim.cmd("runtime plugin/doc_preview.lua")

-- Paragraph i is source line 3i-2 and preview line 2i-1.
local function open()
  require("doc_preview.config").setup({})
  vim.cmd("enew")
  local src = vim.api.nvim_get_current_buf()
  local t = {}
  for i = 1, 40 do
    vim.list_extend(t, { "p" .. i, "", "" })
  end
  vim.api.nvim_buf_set_lines(src, 0, -1, false, t)
  vim.cmd("DocPreview open")
  local s = doc_preview.session(src)
  assert.is_true(doc_preview.wait(s, 2000))
  vim.wait(50)
  return s
end

local function cursor(win)
  return vim.api.nvim_win_get_cursor(win)[1]
end

describe("DocPreview cursor sync and sync commands", function()
  after_each(function()
    render.test_hook = nil
    require("doc_preview.config").setup({})
    pcall(vim.cmd, "only")
  end)

  it("set_enabled(false) stops mirroring both ways, true resumes", function()
    local s = open()
    sync.set_enabled(s, false)
    local before = cursor(s.prev_win)
    vim.api.nvim_win_set_cursor(s.src_win, { 31, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.src_buf })
    assert.equals(before, cursor(s.prev_win))

    vim.api.nvim_set_current_win(s.prev_win)
    vim.api.nvim_win_set_cursor(s.prev_win, { 5, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.prev_buf })
    assert.equals(31, cursor(s.src_win))

    sync.set_enabled(s, true)
    assert.equals(31, cursor(s.src_win))
    assert.equals(21, cursor(s.prev_win))
    vim.api.nvim_win_set_cursor(s.prev_win, { 5, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.prev_buf })
    assert.equals(7, cursor(s.src_win))
    doc_preview.close()
  end)

  it("q closes session, window and buffer", function()
    local s = open()
    vim.api.nvim_set_current_win(s.prev_win)
    vim.api.nvim_feedkeys("q", "x", false)
    assert.is_nil(doc_preview.session(s.src_buf))
    assert.is_false(vim.api.nvim_win_is_valid(s.prev_win))
    assert.is_false(vim.api.nvim_buf_is_valid(s.prev_buf))
  end)

  it("leaves no leaked maps after close", function()
    local function count(maps)
      local n = 0
      for _, m in ipairs(maps) do
        if m.lhs == "q" then
          n = n + 1
        end
      end
      return n
    end
    local globals = count(vim.api.nvim_get_keymap("n"))
    local s = open()
    assert.equals(1, count(vim.api.nvim_buf_get_keymap(s.prev_buf, "n")))
    assert.equals(0, count(vim.api.nvim_buf_get_keymap(s.src_buf, "n")))
    doc_preview.close()
    assert.equals(0, count(vim.api.nvim_buf_get_keymap(s.src_buf, "n")))
    assert.equals(globals, count(vim.api.nvim_get_keymap("n")))
  end)

  it(":DocPreview sync off/on toggles mirroring", function()
    local s = open()
    vim.cmd("DocPreview sync off")
    local before = cursor(s.prev_win)
    vim.api.nvim_win_set_cursor(s.src_win, { 31, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.src_buf })
    assert.equals(before, cursor(s.prev_win))
    vim.cmd("DocPreview sync on")
    assert.equals(21, cursor(s.prev_win))
    doc_preview.close()
  end)

  it(":DocPreview sync with a bad argument notifies an error", function()
    open()
    local msgs = {}
    local orig = vim.notify
    vim.notify = function(m, l)
      table.insert(msgs, { m, l })
    end
    vim.cmd("DocPreview sync maybe")
    vim.cmd("DocPreview sync")
    vim.notify = orig
    assert.equals(2, #msgs)
    assert.equals(vim.log.levels.ERROR, msgs[1][2])
    doc_preview.close()
  end)

  it("completes sync arguments", function()
    assert.same({ "on", "off" }, doc_preview.complete("", "DocPreview sync "))
    assert.same({ "off" }, doc_preview.complete("of", "DocPreview sync of"))
    assert.same({ "sync" }, doc_preview.complete("s", "DocPreview s"))
  end)
end)
