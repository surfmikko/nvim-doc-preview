local doc_preview = require("doc_preview")
local render = require("doc_preview.document.render")

vim.cmd("runtime plugin/doc_preview.lua")

local function open_at(line)
  vim.o.columns = 400
  vim.cmd("edit doc/architecture.md")
  local src = vim.api.nvim_get_current_buf()
  vim.cmd("DocPreview open")
  local s = doc_preview.session(src)
  assert.is_true(doc_preview.wait(s, 2000))
  vim.wait(50)
  vim.api.nvim_win_set_height(s.src_win, 15)
  vim.api.nvim_win_set_height(s.prev_win, 15)
  vim.api.nvim_set_current_win(s.src_win)
  vim.api.nvim_win_set_cursor(s.src_win, { line, 0 })
  vim.cmd("normal! zz")
  return s
end

-- Run a normal command and raise the events the UI loop would.
local function keys(s, cmd, seen)
  if cmd ~= "" then
    vim.api.nvim_win_call(s.src_win, function()
      vim.cmd("normal! " .. cmd)
    end)
  end
  vim.cmd("redraw")
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = s.src_buf })
  for _, w in ipairs({ s.src_win, s.prev_win }) do
    local top = vim.fn.getwininfo(w)[1].topline
    if seen[w] ~= top then
      seen[w] = top
      vim.api.nvim_exec_autocmds("WinScrolled", { pattern = tostring(w) })
    end
  end
  vim.wait(5)
  return {
    src = vim.api.nvim_win_get_cursor(s.src_win)[1],
    stop = vim.fn.getwininfo(s.src_win)[1].topline,
    cur = vim.api.nvim_win_get_cursor(s.prev_win)[1],
    top = vim.fn.getwininfo(s.prev_win)[1].topline,
  }
end

local function headings()
  local t = {}
  for i, l in ipairs(vim.fn.readfile("doc/architecture.md")) do
    if l:match("^#+ ") then
      t[#t + 1] = i
    end
  end
  return t
end

-- Put `line` mid-window and let the sync settle.
local function center(s, line, seen)
  vim.api.nvim_win_set_cursor(s.src_win, { line, 0 })
  vim.cmd("normal! zz")
  return keys(s, "", seen)
end

describe("DocPreview scroll sync with a heading mid-window", function()
  local s
  before_each(function()
    s = open_at(1)
  end)
  after_each(function()
    doc_preview.close()
    render.test_hook = nil
    pcall(vim.cmd, "only")
  end)

  it("keeps the preview topline still while only the cursor moves", function()
    local seen = {}
    for _, h in ipairs(headings()) do
      if h > 20 then
        local home = center(s, h, seen)
        for _, cmd in ipairs({ "k", "j", "j", "k", "5k", "10j", "5k", "k", "3j", "j" }) do
          local r = keys(s, cmd, seen)
          local msg = " on " .. cmd .. " at heading line " .. h
          assert.equals(home.stop, r.stop, "source scrolled" .. msg)
          -- A wrapped table row maps many preview rows to one source line, so a
          -- move may legitimately leave the home window; then it must scroll.
          local left_home = r.cur < home.top or r.cur >= home.top + 15
          assert.is_true(left_home or home.top == r.top, "preview topline jumped" .. msg)
          assert.is_true(r.cur >= r.top and r.cur < r.top + 15, "cursor out of view" .. msg)
        end
        assert.same(home, keys(s, "3k", seen), "did not return to the same view at " .. h)
      end
    end
  end)

  it("preview cursor never moves against the direction of travel", function()
    local seen = {}
    center(s, 60, seen)
    for _, key in ipairs({ "j", "k" }) do
      local sign = key == "j" and 1 or -1
      local prev
      for i = 1, 60 do
        local r = keys(s, key, seen)
        if prev then
          local msg = key .. " step " .. i
          assert.is_true(sign * (r.cur - prev.cur) >= 0, "cursor went back at " .. msg)
          assert.is_true(sign * (r.top - prev.top) >= 0, "topline went back at " .. msg)
        end
        prev = r
      end
    end
  end)
end)
