local config = require("doc_preview.config")
local doc_preview = require("doc_preview")
local session = require("doc_preview.session")
local text = require("doc_preview.core.text")

vim.cmd("runtime plugin/doc_preview.lua")

local STATE =
  { "stateDiagram-v2", "direction LR", "[*] --> Idle", "Idle --> Busy : go", "Busy --> [*]" }

local function fenced(body)
  local lines = { "before", "", "```mermaid" }
  vim.list_extend(lines, body)
  vim.list_extend(lines, { "```", "", "after" })
  return lines
end

describe("DocPreview mermaid state diagram", function()
  after_each(function()
    doc_preview.close()
    config.setup({})
    pcall(vim.cmd, "only")
  end)

  local function open(lines, name)
    vim.cmd("enew")
    local src = vim.api.nvim_get_current_buf()
    if name then
      vim.api.nvim_buf_set_name(src, vim.fn.tempname() .. name)
    end
    vim.api.nvim_buf_set_lines(src, 0, -1, false, lines)
    vim.cmd("DocPreview open vsplit")
    local s = doc_preview.session(src)
    assert.is_true(doc_preview.wait(s, 2000))
    vim.wait(50)
    return s
  end

  local function prev_lines(s)
    return vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false)
  end

  local function has(lines, str)
    return table.concat(lines, "\n"):find(str, 1, true) ~= nil
  end

  local function assert_fits(s)
    for _, l in ipairs(prev_lines(s)) do
      assert.is_true(text.width(l) <= s.width, l)
    end
  end

  local function resize(s, n)
    vim.api.nvim_win_set_width(s.prev_win, n)
    vim.api.nvim_exec_autocmds("VimResized", {})
    vim.wait(500, function()
      return session.width(s) == n and s.width == n
    end)
    assert.is_true(doc_preview.wait(s, 2000))
  end

  it("renders a fenced state block and a .mmd state file", function()
    local s = open(fenced({ "stateDiagram-v2", "[*] --> Idle", "Idle --> [*]" }))
    assert.is_true(has(prev_lines(s), "●"))
    assert.is_true(has(prev_lines(s), "◉"))
    assert.is_true(has(prev_lines(s), "Idle"))
    assert_fits(s)
    doc_preview.close()
    s = open({ "stateDiagram-v2", "state c <<choice>>", "A --> c", "c --> B" }, ".mmd")
    assert.is_true(has(prev_lines(s), "<   >"))
    assert_fits(s)
  end)

  it("re-applies the width fallbacks on resize", function()
    local s = open(fenced(STATE))
    resize(s, 80)
    assert.is_true(has(prev_lines(s), "▶"), "left to right at 80")
    resize(s, 14)
    assert_fits(s)
    assert.is_false(has(prev_lines(s), "▶"), "top-down at 14")
    assert.is_true(has(prev_lines(s), "▼"))
    resize(s, 8)
    assert_fits(s)
    assert.is_true(has(prev_lines(s), "stat"), "boxed source at 8")
    resize(s, 80)
    assert.is_true(has(prev_lines(s), "▶"), "fallback undone when wide again")
  end)
end)
