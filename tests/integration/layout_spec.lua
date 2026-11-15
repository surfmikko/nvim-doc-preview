local config = require("doc_preview.config")
local doc_preview = require("doc_preview")

vim.cmd("runtime plugin/doc_preview.lua")

local function open_with(opts)
  config.setup(opts)
  vim.cmd("enew")
  local src = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(src, 0, -1, false, { "one", "", "", "two", "", "", "three" })
  vim.cmd("DocPreview open")
  local s = doc_preview.session(src)
  if s then
    assert.is_true(doc_preview.wait(s, 2000))
  end
  return s, src
end

describe("DocPreview layouts", function()
  after_each(function()
    pcall(vim.cmd, "only")
    config.setup({})
  end)

  it("vsplit opens the preview to the right", function()
    local s = open_with({ layout = "vsplit" })
    local sp = vim.api.nvim_win_get_position(s.prev_win)
    local ss = vim.api.nvim_win_get_position(s.src_win)
    assert.is_true(sp[2] > ss[2])
    assert.equals(ss[1], sp[1])
  end)

  it("hsplit opens the preview below with the same width", function()
    local s = open_with({ layout = "hsplit" })
    local sp = vim.api.nvim_win_get_position(s.prev_win)
    local ss = vim.api.nvim_win_get_position(s.src_win)
    assert.is_true(sp[1] > ss[1])
    assert.equals(vim.api.nvim_win_get_width(s.src_win), vim.api.nvim_win_get_width(s.prev_win))
  end)

  it("open hsplit overrides a vsplit config for that session only", function()
    local s, src = open_with({ layout = "vsplit" })
    assert.equals("vsplit", s.layout)
    doc_preview.close()
    vim.cmd("DocPreview open hsplit")
    s = doc_preview.session(src)
    assert.equals("hsplit", s.layout)
    assert.is_true(vim.api.nvim_win_get_position(s.prev_win)[1] > 0)
    doc_preview.close()
    vim.cmd("DocPreview open")
    assert.equals("vsplit", doc_preview.session(src).layout)
  end)

  it("same-layout open keeps the session; another layout reopens", function()
    local s, src = open_with({})
    vim.cmd("DocPreview open vsplit")
    assert.equals(s, doc_preview.session(src))
    vim.cmd("DocPreview open hsplit")
    local s2 = doc_preview.session(src)
    assert.is_true(s2 ~= s)
    assert.is_true(s.closed)
    assert.is_false(vim.api.nvim_win_is_valid(s.prev_win))
    assert.equals("hsplit", s2.layout)
    assert.equals(2, #vim.api.nvim_list_wins())
  end)

  it("toggle takes a layout and closes an existing session", function()
    local _, src = open_with({})
    vim.cmd("DocPreview toggle hsplit")
    assert.is_nil(doc_preview.session(src))
    vim.cmd("DocPreview toggle hsplit")
    assert.equals("hsplit", doc_preview.session(src).layout)
  end)

  it("toggle closes a session opened by plain open in any layout", function()
    for _, layout in ipairs({ "vsplit", "hsplit", "replace" }) do
      local _, src = open_with({})
      vim.cmd("DocPreview open " .. layout)
      assert.equals(layout, doc_preview.session(src).layout)
      vim.cmd("DocPreview toggle")
      assert.is_nil(doc_preview.session(src))
      vim.cmd("DocPreview open " .. layout)
      vim.cmd("DocPreview toggle replace")
      assert.is_nil(doc_preview.session(src))
      pcall(vim.cmd, "only")
    end
  end)

  it("invalid layout argument opens nothing", function()
    local msgs = {}
    local orig = vim.notify
    vim.notify = function(m, l)
      table.insert(msgs, { m, l })
    end
    config.setup({})
    vim.cmd("enew")
    local src = vim.api.nvim_get_current_buf()
    local wins = #vim.api.nvim_list_wins()
    vim.cmd("DocPreview open bogus")
    vim.cmd("DocPreview toggle bogus")
    vim.notify = orig
    assert.is_nil(doc_preview.session(src))
    assert.equals(wins, #vim.api.nvim_list_wins())
    assert.equals(2, #msgs)
    assert.truthy(msgs[1][1]:find("DocPreview: ", 1, true))
    assert.truthy(msgs[1][1]:find("vsplit|hsplit|replace", 1, true))
    assert.equals(vim.log.levels.ERROR, msgs[1][2])
  end)

  it("completes layout names after open and toggle", function()
    local all = { "vsplit", "hsplit", "replace" }
    assert.same(all, doc_preview.complete("", "DocPreview open "))
    assert.same(all, doc_preview.complete("", "DocPreview toggle "))
    assert.same({ "hsplit" }, doc_preview.complete("h", "DocPreview open h"))
    assert.same({ "open" }, doc_preview.complete("op", "DocPreview op"))
  end)

  it("replace shows the preview in the same window and flips back", function()
    config.setup({})
    vim.cmd("enew")
    local src = vim.api.nvim_get_current_buf()
    local lines = {}
    for i = 1, 80 do
      lines[i] = "line " .. i
    end
    vim.api.nvim_buf_set_lines(src, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { 50, 2 })
    vim.cmd("normal! zt")
    local win = vim.api.nvim_get_current_win()
    local view = vim.fn.winsaveview()
    local wins = #vim.api.nvim_list_wins()
    vim.cmd("DocPreview open replace")
    local s = doc_preview.session(src)
    assert.equals("replace", s.layout)
    assert.equals(wins, #vim.api.nvim_list_wins())
    assert.equals(s.prev_buf, vim.api.nvim_win_get_buf(win))
    assert.equals(win, s.prev_win)
    assert.is_true(doc_preview.wait(s, 2000))
    vim.cmd("DocPreview toggle")
    assert.is_nil(doc_preview.session(src))
    assert.equals(wins, #vim.api.nvim_list_wins())
    assert.equals(src, vim.api.nvim_win_get_buf(win))
    assert.same(view, vim.fn.winsaveview())
  end)

  local function replace_open(opts)
    config.setup(opts or {})
    vim.cmd("enew")
    local src = vim.api.nvim_get_current_buf()
    local lines = {}
    for i = 1, 80 do
      lines[#lines + 1] = "paragraph " .. i
      lines[#lines + 1] = ""
    end
    vim.api.nvim_buf_set_lines(src, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { 61, 0 })
    vim.cmd("normal! zt")
    vim.wo.wrap = true
    vim.cmd("DocPreview open replace")
    local s = doc_preview.session(src)
    assert.is_true(doc_preview.wait(s, 2000))
    return s, src
  end

  it("replace open maps the cursor and restores options on flip back", function()
    local s, src = replace_open()
    local win = s.prev_win
    local line, top = vim.fn.line(".", win), vim.fn.getwininfo(win)[1].topline
    assert.equals(s.output:src_to_out(61), line)
    assert.equals(line, top)
    assert.is_false(vim.wo[win].wrap)
    doc_preview.close()
    assert.is_true(vim.wo[win].wrap)
    assert.equals(src, vim.api.nvim_win_get_buf(win))
    assert.equals(61, vim.api.nvim_win_get_cursor(win)[1])
  end)

  it("replace flip back maps a moved preview cursor", function()
    local s, src = replace_open()
    local win = s.prev_win
    local out = s.output:src_to_out(41)
    vim.api.nvim_win_set_cursor(win, { out, 0 })
    doc_preview.close()
    assert.equals(src, vim.api.nvim_win_get_buf(win))
    assert.equals(41, vim.api.nvim_win_get_cursor(win)[1])
  end)

  it("replace keeps rendering while the source is hidden and keeps edits", function()
    local s, src = open_with({ layout = "replace" })
    vim.api.nvim_buf_call(src, function()
      vim.api.nvim_buf_set_lines(src, 0, 1, false, { "# changed" })
    end)
    vim.cmd("doautocmd TextChanged")
    require("doc_preview.sync").changed(s)
    assert.is_true(doc_preview.wait(s, 2000))
    local out = table.concat(vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false), "\n")
    assert.truthy(out:find("changed", 1, true))
    assert.is_true(vim.bo[src].modified)
    vim.cmd("DocPreview toggle")
    assert.is_nil(doc_preview.session(src))
    assert.equals("# changed", vim.api.nvim_buf_get_lines(src, 0, 1, false)[1])
    assert.is_true(vim.bo[src].modified)
  end)

  local function count_autocmds()
    local n = 0
    for _, a in ipairs(vim.api.nvim_get_autocmds({})) do
      if a.group_name and a.group_name:match("^DocPreview%d") then
        n = n + 1
      end
    end
    return n
  end

  local function assert_torn_down(s, src)
    assert.is_nil(doc_preview.session(src))
    assert.is_true(s.timer:is_closing())
    assert.is_nil(s.job)
    assert.equals(0, count_autocmds())
    assert.is_false(vim.api.nvim_buf_is_valid(s.prev_buf or -1))
    assert.is_true(vim.api.nvim_buf_is_valid(src))
    assert.same({}, vim.api.nvim_buf_get_extmarks(src, s.ns, 0, -1, {}))
  end

  it("replace attaches no cursor/scroll autocmds and sync on/off is a no-op", function()
    local s = replace_open()
    for _, a in ipairs(vim.api.nvim_get_autocmds({ group = s.augroup })) do
      assert.is_false(
        a.event == "WinScrolled" or a.event == "CursorMoved" or a.event == "WinClosed"
      )
    end
    vim.cmd("DocPreview sync off")
    vim.cmd("DocPreview sync on")
    assert.is_not_nil(doc_preview.session(s.src_buf))
    assert.equals(s.prev_buf, vim.api.nvim_win_get_buf(s.prev_win))
    doc_preview.close()
  end)

  it("replace: closing the window tears the session down", function()
    local s, src = replace_open()
    vim.cmd("split | enew")
    vim.api.nvim_win_close(s.prev_win, true)
    assert_torn_down(s, src)
  end)

  it("replace: showing another buffer wipes the preview without view restore", function()
    local s, src = replace_open()
    local win = s.prev_win
    vim.api.nvim_buf_set_lines(src, 0, 1, false, { "edited" })
    vim.cmd("enew")
    local other = vim.api.nvim_get_current_buf()
    assert_torn_down(s, src)
    assert.equals(other, vim.api.nvim_win_get_buf(win))
    assert.is_true(vim.wo[win].wrap)
    assert.is_true(vim.bo[src].modified)
    assert.equals("edited", vim.api.nvim_buf_get_lines(src, 0, 1, false)[1])
  end)

  it("replace re-renders when the shared window width changes", function()
    local s = replace_open()
    local old = s.width
    local gen = s.generation
    vim.cmd("vsplit")
    vim.api.nvim_set_current_win(s.prev_win)
    vim.api.nvim_win_set_width(s.prev_win, 30)
    vim.api.nvim_exec_autocmds("VimResized", {})
    assert.is_true(doc_preview.wait(s, 2000))
    assert.equals(30, s.width)
    assert.is_true(old > s.width and s.generation > gen)
    doc_preview.close()
    assert_torn_down(s, s.src_buf)
  end)
end)
