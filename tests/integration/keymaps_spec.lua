local config = require("doc_preview.config")
local doc_preview = require("doc_preview")

vim.cmd("runtime plugin/doc_preview.lua")

local LAYOUTS = { "vsplit", "hsplit", "replace" }

local function buf_maps(buf)
  local t = {}
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    t[m.lhs] = true
  end
  return t
end

local function new_source()
  vim.cmd("enew")
  local src = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(src, 0, -1, false, { "one", "", "two" })
  return src
end

local function open_with(opts, layout)
  doc_preview.setup(opts)
  local src = new_source()
  vim.cmd("DocPreview open " .. layout)
  local s = doc_preview.session(src)
  assert.is_true(doc_preview.wait(s, 2000))
  return s
end

local function count_autocmds()
  return #vim.api.nvim_get_autocmds({})
end

describe("keymaps option", function()
  after_each(function()
    pcall(vim.cmd, "only")
    doc_preview.setup({})
  end)

  it("defaults to only the preview-local close map", function()
    assert.same({ close = "q" }, config.options.keymaps)
    assert.equals("", vim.fn.maparg("<leader>p", "n"))
  end)

  for _, layout in ipairs(LAYOUTS) do
    it("q closes the preview in " .. layout, function()
      local s = open_with({}, layout)
      assert.is_true(buf_maps(s.prev_buf)["q"])
      vim.api.nvim_set_current_win(s.prev_win)
      vim.api.nvim_feedkeys("q", "x", false)
      assert.is_nil(doc_preview.session(s.src_buf))
      assert.is_false(vim.api.nvim_buf_is_valid(s.prev_buf))
    end)

    it("custom close lhs and close = false in " .. layout, function()
      local s = open_with({ keymaps = { close = "x" } }, layout)
      local m = buf_maps(s.prev_buf)
      assert.is_true(m["x"])
      assert.is_nil(m["q"])
      doc_preview.close()
      s = open_with({ keymaps = { close = false } }, layout)
      assert.same({}, buf_maps(s.prev_buf))
      doc_preview.close()
      s = open_with({ keymaps = false }, layout)
      assert.same({}, buf_maps(s.prev_buf))
    end)

    it("toggle after plain open closes in " .. layout, function()
      local s = open_with({}, layout)
      vim.cmd("DocPreview toggle")
      assert.is_nil(doc_preview.session(s.src_buf))
    end)
  end

  it("rejects the removed toggle and jump_to_source keys", function()
    for _, key in ipairs({ "toggle", "jump_to_source" }) do
      local ok, err = pcall(doc_preview.setup, { keymaps = { [key] = "<CR>" } })
      assert.is_false(ok)
      assert.truthy(err:find("unknown key keymaps." .. key, 1, true), err)
      assert.truthy(err:find("valid keys: close", 1, true), err)
    end
  end)

  it("leaks no autocmds or maps after toggle replace in and out", function()
    local src = new_source()
    local globals = #vim.api.nvim_get_keymap("n")
    local before = count_autocmds()
    vim.cmd("DocPreview toggle replace")
    local s = doc_preview.session(src)
    assert.is_true(doc_preview.wait(s, 2000))
    vim.cmd("DocPreview toggle replace")
    assert.is_nil(doc_preview.session(src))
    assert.is_false(vim.api.nvim_buf_is_valid(s.prev_buf))
    assert.is_nil(buf_maps(src)["q"])
    assert.equals(globals, #vim.api.nvim_get_keymap("n"))
    assert.equals(before, count_autocmds())
  end)
end)
