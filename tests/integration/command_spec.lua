local config = require("doc_preview.config")
local doc_preview = require("doc_preview")
local render = require("doc_preview.document.render")

vim.cmd("runtime plugin/doc_preview.lua")

local function new_source()
  vim.cmd("enew")
  local src = vim.api.nvim_get_current_buf()
  local t = {}
  for i = 1, 40 do
    vim.list_extend(t, { "p" .. i, "", "" })
  end
  vim.api.nvim_buf_set_lines(src, 0, -1, false, t)
  return src
end

describe("bare :DocPreview", function()
  after_each(function()
    render.test_hook = nil
    pcall(vim.cmd, "only")
    config.setup({})
  end)

  it("toggles the preview", function()
    local src = new_source()
    vim.cmd("DocPreview")
    local s = doc_preview.session(src)
    assert.is_truthy(s)
    assert.is_true(doc_preview.wait(s, 2000))
    vim.cmd("DocPreview")
    assert.is_nil(doc_preview.session(src))
  end)

  it("sync without argument still errors", function()
    local src = new_source()
    vim.cmd("DocPreview open")
    local msgs = {}
    local orig = vim.notify
    vim.notify = function(m)
      msgs[#msgs + 1] = m
    end
    vim.cmd("DocPreview sync")
    vim.notify = orig
    assert.is_truthy(msgs[1] and msgs[1]:find("sync expects", 1, true))
    doc_preview.close()
    assert.is_nil(doc_preview.session(src))
  end)
end)

describe("sync config flags", function()
  after_each(function()
    pcall(vim.cmd, "only")
    config.setup({})
  end)

  local function open_with(sync_cfg)
    config.setup({ sync = sync_cfg })
    local src = new_source()
    vim.cmd("DocPreview open")
    local s = doc_preview.session(src)
    assert.is_true(doc_preview.wait(s, 2000))
    vim.wait(50)
    return s
  end

  it("cursor = false and scroll = false start with sync disabled until sync on", function()
    local s = open_with({ cursor = false, scroll = false })
    assert.is_false(s.sync_enabled)
    vim.api.nvim_set_current_win(s.src_win)
    vim.api.nvim_win_set_cursor(s.src_win, { 31, 0 })
    vim.wait(100)
    assert.equals(1, vim.api.nvim_win_get_cursor(s.prev_win)[1])
    vim.cmd("DocPreview sync on")
    vim.wait(100)
    assert.is_true(vim.api.nvim_win_get_cursor(s.prev_win)[1] > 1)
  end)

  it("cursor = false alone stops cursor mirroring only", function()
    local s = open_with({ cursor = false, scroll = true })
    assert.is_true(s.sync_enabled)
    vim.api.nvim_set_current_win(s.src_win)
    vim.api.nvim_win_set_cursor(s.src_win, { 2, 0 })
    vim.wait(100)
    assert.equals(1, vim.api.nvim_win_get_cursor(s.prev_win)[1])
  end)
end)
