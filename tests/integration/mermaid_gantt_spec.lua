local config = require("doc_preview.config")
local doc_preview = require("doc_preview")
local session = require("doc_preview.session")
local text = require("doc_preview.core.text")

vim.cmd("runtime plugin/doc_preview.lua")

local PIE = {
  "gantt",
  "title Plan",
  "section Build",
  "Design :done, d1, 2024-01-01, 3d",
  "Code :active, c1, after d1, 1w",
  "Go :milestone, m1, 2024-01-15, 0d",
}

local function fenced(body)
  local lines = { "before", "", "```mermaid" }
  vim.list_extend(lines, body)
  vim.list_extend(lines, { "```", "", "after" })
  return lines
end

describe("DocPreview mermaid gantt chart", function()
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

  local function prev_text(s)
    return table.concat(vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false), "\n")
  end

  local function assert_fits(s)
    for _, l in ipairs(vim.api.nvim_buf_get_lines(s.prev_buf, 0, -1, false)) do
      assert.is_true(text.width(l) <= s.width, l)
    end
  end

  it("renders a fenced gantt block and a .mmd gantt file", function()
    local s = open(fenced(PIE))
    assert.truthy(prev_text(s):find("Design █", 1, true))
    assert.truthy(prev_text(s):find("01-01", 1, true))
    assert.truthy(prev_text(s):find("after", 1, true))
    assert_fits(s)
    doc_preview.close()
    s = open(PIE, ".mmd")
    assert.truthy(prev_text(s):find("◆", 1, true))
    assert_fits(s)
  end)

  it("re-applies the width policy on resize", function()
    local s = open(fenced(PIE))
    vim.api.nvim_win_set_width(s.prev_win, 20)
    vim.api.nvim_exec_autocmds("VimResized", {})
    vim.wait(500, function()
      return session.width(s) == 20 and s.width == 20
    end)
    assert.is_true(doc_preview.wait(s, 2000))
    assert_fits(s)
    assert.truthy(prev_text(s):find("Design", 1, true))
  end)
end)
